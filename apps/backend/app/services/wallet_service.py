"""FEAT-043 (Admin-Only Escrow Release) + FEAT-044 (Host/Agency Virtual
Wallet) business logic.

Money-safety invariants this module enforces:
  - A Transaction is only ever released once (`release_transaction` is
    idempotent-guarded on `txn.status`, and the whole operation -- status
    flip, Wallet upsert, WalletTransaction ledger write -- happens inside a
    single DB transaction so a crash mid-way can never credit a wallet
    without also flipping the source Transaction, or vice versa).
  - `Wallet.balance` is a denormalized convenience value; the
    WalletTransaction ledger (immutable, append-only) is the source of
    truth. `balance_after` is captured on every ledger row so the wallet
    balance can always be reconstructed/audited from the ledger alone.
  - Release is Admin-only (enforced by the caller via
    `require_roles(UserRole.DEDUKE_ADMIN)` in the API layer, not here) and
    always writes an AuditLogEntry (AGENTS.md Behavior Rules).
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.ops import AuditLogEntry
from app.models.transaction import Transaction
from app.models.wallet import Wallet, WalletTransaction
from app.services import dispute_service, email_service, push_service

logger = logging.getLogger("app.services.wallet_service")

# FEAT-043 AC: the Release Funds screen only ever surfaces transactions
# that have actually been paid -- still-escrowed (RELEASABLE_STATUS) or
# already released (RELEASED_STATUS). Never 'held'/'pending_payment' (not
# paid yet) or 'refunded'/'failed'/'expired' (never reached this flow at
# all) -- those aren't part of this screen's log either way.
RELEASABLE_STATUS = "payment_received"
RELEASED_STATUS = "released_to_wallet"

# Filter values for `list_release_queue` -- mirrors the Admin Web Console's
# Release Funds screen filter (pending needing action / released as a
# persisted log / both together).
RELEASE_QUEUE_FILTERS = ("pending", "released", "all")


class WalletError(Exception):
    """Raised for any wallet-service-level validation failure. Callers
    (app/api/v1/wallet.py) map this to HTTP 400/404 as appropriate."""


async def ensure_wallet(session: AsyncSession, *, owner_id: str) -> Wallet:
    """Returns the owner's Wallet, creating an empty one on first use.
    Called both by `release_transaction` (a payee's very first release may
    be the moment their Wallet is first needed) and by the wallet-read
    endpoints (a payee who has never been released to should still see a
    zero-balance Wallet, not a 404)."""
    result = await session.execute(select(Wallet).where(Wallet.owner_id == owner_id))
    wallet = result.scalar_one_or_none()
    if wallet is not None:
        return wallet

    wallet = Wallet(owner_id=owner_id)
    session.add(wallet)
    await session.flush()
    return wallet


async def list_release_queue(
    session: AsyncSession, *, status_filter: str = "pending", listing_id: str | None = None
) -> list[tuple[Transaction, bool]]:
    """FEAT-043's Release Funds screen. Three filters:
      - 'pending' (default): every still-escrowed `payment_received`
        Transaction, oldest-paid-first -- funds shouldn't sit escrowed
        indefinitely, so the longest-waiting release surfaces first, same
        reasoning as moderation_service's queue ordering.
      - 'released': every already-released `released_to_wallet`
        Transaction, most-recently-released first -- a persisted log of
        completed releases (who released what, and when), not a
        to-do queue, so newest-first reads more naturally here.
      - 'all': both together, oldest-paid-first, for a single combined
        view.
    A released Transaction is never removed from the backing table on
    release (release_transaction only flips its status in place) -- so
    this filter is purely a WHERE clause, not a separate log table; the
    'released' filter is what makes that history visibly persist on this
    screen rather than a row simply disappearing once acted on.

    Returns `(Transaction, has_open_dispute)` pairs -- FEAT-043/FEAT-026
    coupling: an Admin deciding whether to release funds needs to know a
    dispute is actively being investigated against that same transaction
    WITHOUT this screen re-implementing the Disputes screen's own UI (see
    `release_transaction`'s hard block below for the actual enforcement;
    this flag is what lets the Release Funds screen surface a warning and
    disable the action before even attempting a call that would fail).
    """
    if status_filter not in RELEASE_QUEUE_FILTERS:
        raise WalletError(f"status_filter must be one of {RELEASE_QUEUE_FILTERS}")

    stmt = select(Transaction)
    if status_filter == "pending":
        stmt = stmt.where(Transaction.status == RELEASABLE_STATUS).order_by(
            Transaction.paid_at.asc()
        )
    elif status_filter == "released":
        stmt = stmt.where(Transaction.status == RELEASED_STATUS).order_by(
            Transaction.released_at.desc()
        )
    else:
        stmt = stmt.where(
            Transaction.status.in_((RELEASABLE_STATUS, RELEASED_STATUS))
        ).order_by(Transaction.paid_at.asc())

    if listing_id:
        stmt = stmt.where(Transaction.listing_id == listing_id)

    result = await session.execute(stmt)
    transactions = list(result.scalars().all())
    if not transactions:
        return []

    open_dispute_ids = await dispute_service.list_open_dispute_transaction_ids(
        session, transaction_ids=[t.id for t in transactions]
    )
    return [(t, t.id in open_dispute_ids) for t in transactions]


async def release_transaction(
    session: AsyncSession, *, transaction_id: str, admin_id: str
) -> Transaction:
    """FEAT-043: the sole path by which a Transaction's escrowed funds
    become a Wallet credit. Atomic: status flip + Wallet upsert +
    WalletTransaction ledger write all happen inside one DB transaction
    (the caller's `async with session.begin()`), so this function itself
    does not commit -- see app/api/v1/wallet.py's release endpoint.
    """
    result = await session.execute(
        select(Transaction).where(Transaction.id == transaction_id).with_for_update()
    )
    txn = result.scalar_one_or_none()
    if txn is None:
        raise WalletError("Transaction not found.")
    if txn.status == "released_to_wallet":
        raise WalletError("This transaction has already been released.")
    if txn.status != RELEASABLE_STATUS:
        raise WalletError(
            f"Only transactions with status '{RELEASABLE_STATUS}' can be released "
            f"(this transaction is '{txn.status}')."
        )

    # FEAT-043/FEAT-026 coupling (money safety): a released_to_wallet
    # transaction can't be refunded through the normal dispute-resolution
    # path (dispute_service.resolve_dispute's own released_to_wallet
    # guard) -- so funds must never be released while a dispute against
    # this same transaction is still under active investigation. Hard
    # block, not just a UI warning: this is the actual enforcement point,
    # regardless of what the Release Funds screen did or didn't surface.
    open_dispute_ids = await dispute_service.list_open_dispute_transaction_ids(
        session, transaction_ids=[txn.id]
    )
    if txn.id in open_dispute_ids:
        raise WalletError(
            "This transaction has an open dispute under investigation -- resolve the "
            "dispute before releasing funds."
        )

    wallet = await ensure_wallet(session, owner_id=txn.payee_id)
    new_balance = round(wallet.balance + txn.net_payout_amount, 2)

    session.add(
        WalletTransaction(
            wallet_id=wallet.id,
            direction="credit",
            amount=txn.net_payout_amount,
            source_type="transaction_release",
            source_id=txn.id,
            balance_after=new_balance,
        )
    )
    wallet.balance = new_balance
    wallet.updated_at = datetime.now(UTC)
    session.add(wallet)

    txn.status = "released_to_wallet"
    txn.released_at = datetime.now(UTC)
    txn.released_by_admin_id = admin_id
    session.add(txn)

    session.add(
        AuditLogEntry(
            actor_id=admin_id,
            action_type="escrow_funds_released",
            target_type="Transaction",
            target_id=txn.id,
            notes=f"released net_payout_amount={txn.net_payout_amount} to wallet={wallet.id}",
        )
    )

    await session.flush()
    await session.refresh(txn)
    return txn


async def notify_release(session: AsyncSession, *, txn: Transaction) -> None:
    """Fires the payee's release notification -- deliberately split from
    `release_transaction` (which only flushes, never commits) so the
    caller commits the atomic release first, then notifies only once that
    has actually landed. Notification failures must never roll back a
    release that already succeeded (AGENTS.md "log and continue")."""
    context = {
        "transaction_id": txn.id,
        "net_payout_amount": txn.net_payout_amount,
    }
    await email_service.notify_user(
        session,
        user_id=txn.payee_id,
        template=email_service.ESCROW_FUNDS_RELEASED,
        context=context,
    )
    await push_service.notify_user(
        session,
        user_id=txn.payee_id,
        template=push_service.ESCROW_FUNDS_RELEASED,
        context=context,
    )


async def get_wallet_transactions(
    session: AsyncSession, *, wallet_id: str, limit: int = 50, before_id: str | None = None
) -> list[WalletTransaction]:
    """Newest-first ledger listing for FEAT-044's wallet transaction
    history. Cursor-based (keyset) pagination per AGENTS.md convention --
    `before_id` is the last-seen WalletTransaction.id from the previous
    page; since ledger rows are immutable and created_at is monotonic per
    insert, filtering on `id < before_id` after an id-tiebreaked ORDER BY
    is stable across pages even for same-millisecond inserts.
    """
    stmt = (
        select(WalletTransaction)
        .where(WalletTransaction.wallet_id == wallet_id)
        .order_by(WalletTransaction.created_at.desc(), WalletTransaction.id.desc())
        .limit(limit)
    )
    if before_id is not None:
        cursor_row = await session.get(WalletTransaction, before_id)
        if cursor_row is not None:
            stmt = stmt.where(
                (WalletTransaction.created_at < cursor_row.created_at)
                | (
                    (WalletTransaction.created_at == cursor_row.created_at)
                    & (WalletTransaction.id < cursor_row.id)
                )
            )
    result = await session.execute(stmt)
    return list(result.scalars().all())
