"""Dispute & Refund Management business logic -- FEAT-026.

Guests/hosts raise a dispute against one of their own transactions from
Transaction History (mobile, POST /v1/disputes); Staff/Admin review,
assign, and resolve them via the Admin Web Console (screens.md Screen 24,
same /v1/disputes/* endpoints, role-gated). Resolving with a refund calls
Paystack's refund API (payment_service.refund_paystack_transaction) and
marks the linked Transaction `refunded` -- never the other way around
(the transaction is only ever marked refunded as a side effect of a real,
successful Paystack refund call, per AGENTS.md Payment Correctness: never
mark a payment outcome from anything other than a verified provider
response).
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.ops import AuditLogEntry, Dispute
from app.models.transaction import Transaction
from app.models.user import User
from app.schemas.dispute import DISPUTE_REASONS, DISPUTE_RESOLUTIONS
from app.services import email_service, payment_service, push_service

logger = logging.getLogger("app.services.dispute_service")


class DisputeError(Exception):
    """Raised for any dispute-service-level validation failure. Callers
    (app/api/v1/disputes.py) map this to HTTP 400/404 as appropriate --
    never to a 500, since these are all caller-correctable input errors."""


# A dispute still under active investigation -- neither resolved
# (DISPUTE_RESOLUTIONS) nor closed. Mirrors resolve_dispute's own
# "already resolved" check (`dispute.status in DISPUTE_RESOLUTIONS or
# dispute.status == 'closed'`), inverted: these are the statuses that
# check treats as NOT yet resolved.
OPEN_DISPUTE_STATUSES = ("open", "under_review")


async def list_open_dispute_transaction_ids(
    session: AsyncSession, *, transaction_ids: list[str]
) -> set[str]:
    """FEAT-043/FEAT-026 coupling: wallet_service consults this before
    ever releasing escrowed funds. A `released_to_wallet` transaction
    can't be refunded through the normal dispute-resolution path (see
    resolve_dispute's own `released_to_wallet` guard below) -- so funds
    must never be released while a dispute against that same transaction
    is still under active investigation, or resolving that dispute fairly
    (refund vs. no refund) becomes a manual, ad-hoc wallet-clawback
    problem instead of the ordinary flow. Returns the subset of
    `transaction_ids` that currently have at least one open dispute.
    """
    if not transaction_ids:
        return set()
    result = await session.execute(
        select(Dispute.transaction_id)
        .where(Dispute.transaction_id.in_(transaction_ids))
        .where(Dispute.status.in_(OPEN_DISPUTE_STATUSES))
    )
    return {row[0] for row in result.all()}


async def create_dispute(
    session: AsyncSession,
    *,
    transaction_id: str,
    raised_by_id: str,
    reason: str,
    description: str,
) -> Dispute:
    if reason not in DISPUTE_REASONS:
        raise DisputeError(f"reason must be one of {DISPUTE_REASONS}")

    transaction = (
        await session.execute(select(Transaction).where(Transaction.id == transaction_id))
    ).scalar_one_or_none()
    if transaction is None:
        raise DisputeError("Transaction not found.")
    if raised_by_id not in (transaction.payer_id, transaction.payee_id):
        raise DisputeError("You can only raise a dispute on your own transaction.")

    dispute = Dispute(
        transaction_id=transaction_id,
        raised_by_id=raised_by_id,
        reason=reason,
        description=description,
    )
    session.add(dispute)
    session.add(
        AuditLogEntry(
            actor_id=raised_by_id,
            action_type="dispute_raised",
            target_type="Dispute",
            target_id=dispute.id,
        )
    )
    await session.commit()
    await session.refresh(dispute)
    return dispute


async def list_disputes(
    session: AsyncSession, *, status_filter: str | None = None, listing_id: str | None = None
) -> list[Dispute]:
    """Newest first -- matches screens.md Screen 24's table default; staff
    filter by status client-side against this same list (small enough
    volume at this stage not to warrant server-side pagination yet, same
    call as moderation_service.list_moderation_queue).

    `listing_id` backs the property detail page's "View all disputes for
    this listing" deep link -- Dispute has no listing_id column of its own
    (it's raised against a Transaction), so this filters via a join rather
    than a direct WHERE.
    """
    stmt = select(Dispute).order_by(Dispute.created_at.desc())
    if status_filter:
        stmt = stmt.where(Dispute.status == status_filter)
    if listing_id:
        stmt = stmt.join(Transaction, Transaction.id == Dispute.transaction_id).where(
            Transaction.listing_id == listing_id
        )
    result = await session.execute(stmt)
    return list(result.scalars().all())


async def get_dispute(session: AsyncSession, dispute_id: str) -> Dispute | None:
    return (
        await session.execute(select(Dispute).where(Dispute.id == dispute_id))
    ).scalar_one_or_none()


async def get_transaction_or_none(
    session: AsyncSession, transaction_id: str
) -> Transaction | None:
    return (
        await session.execute(select(Transaction).where(Transaction.id == transaction_id))
    ).scalar_one_or_none()


async def get_user_name_or_unknown(session: AsyncSession, user_id: str | None) -> str | None:
    if user_id is None:
        return None
    user = await session.get(User, user_id)
    return user.full_name if user is not None else "Unknown"


async def assign_dispute(
    session: AsyncSession, *, dispute: Dispute, staff_id: str, actor_id: str
) -> Dispute:
    staff = await session.get(User, staff_id)
    if staff is None or staff.role not in ("deduke_staff", "deduke_admin"):
        raise DisputeError("staff_id must reference an active Staff or Admin account.")

    dispute.assigned_staff_id = staff_id
    if dispute.status == "open":
        dispute.status = "under_review"
    session.add(dispute)
    session.add(
        AuditLogEntry(
            actor_id=actor_id,
            action_type="dispute_assigned",
            target_type="Dispute",
            target_id=dispute.id,
            notes=f"assigned_to={staff_id}",
        )
    )
    await session.commit()
    await session.refresh(dispute)
    return dispute


async def resolve_dispute(
    session: AsyncSession,
    *,
    dispute: Dispute,
    resolution: str,
    resolution_notes: str,
    refund_amount: float | None,
    actor_id: str,
) -> Dispute:
    if resolution not in DISPUTE_RESOLUTIONS:
        raise DisputeError(f"resolution must be one of {DISPUTE_RESOLUTIONS}")
    if dispute.status in DISPUTE_RESOLUTIONS or dispute.status == "closed":
        raise DisputeError("This dispute has already been resolved.")

    transaction = await get_transaction_or_none(session, dispute.transaction_id)
    if transaction is None:
        raise DisputeError("Linked transaction not found.")

    if resolution == "resolved_refunded":
        if not refund_amount or refund_amount <= 0:
            raise DisputeError("refund_amount is required to resolve with a refund.")
        if transaction.payment_processor_reference is None:
            raise DisputeError("Transaction has no payment reference to refund.")
        # schema.md's Escrow model note: a `released_to_wallet` transaction
        # already had its funds credited into the payee's (possibly
        # aggregated, possibly already-withdrawn) Wallet balance -- a plain
        # Paystack refund here would refund the guest from De-Duke's own
        # settlement account without clawing back anything from the payee's
        # wallet, silently leaving De-Duke short the full amount. Only a
        # still-escrowed `payment_received` transaction (funds sitting in
        # De-Duke's account, never moved to the payee) can be refunded this
        # simply. A released transaction needs a separate, deliberate
        # wallet-clawback process this endpoint does not implement -- fail
        # closed rather than silently do a half-correct refund.
        if transaction.status == "released_to_wallet":
            raise DisputeError(
                "This transaction's funds were already released to the payee's wallet. "
                "Refunding it requires a separate wallet clawback process, not a standard "
                "dispute refund -- contact an Admin to handle this manually."
            )
        try:
            await payment_service.refund_paystack_transaction(
                reference=transaction.payment_processor_reference,
                amount_kobo=int(refund_amount * 100),
            )
        except payment_service.PaystackNotConfiguredError as exc:
            raise DisputeError(str(exc)) from exc
        except Exception as exc:  # noqa: BLE001 -- external call; fail closed, don't resolve
            logger.error(
                "dispute_service: paystack refund failed dispute_id=%s error=%s",
                dispute.id,
                exc,
            )
            raise DisputeError(
                "Refund could not be processed by Paystack. The dispute remains open -- "
                "try again shortly."
            ) from exc

        transaction.status = "refunded"
        session.add(transaction)
        dispute.refund_amount = refund_amount

    dispute.status = resolution
    dispute.resolution_notes = resolution_notes
    dispute.resolved_at = datetime.now(UTC)
    session.add(dispute)
    session.add(
        AuditLogEntry(
            actor_id=actor_id,
            action_type="dispute_resolved",
            target_type="Dispute",
            target_id=dispute.id,
            notes=resolution,
        )
    )
    await session.commit()
    await session.refresh(dispute)

    # Notification failures must never roll back a resolution that already
    # succeeded (and, if applicable, already refunded real money) -- same
    # "log and continue" contract as every other notify_user call site.
    await push_service.notify_user(
        session,
        user_id=dispute.raised_by_id,
        template=push_service.DISPUTE_RESOLVED,
        context={"dispute_id": dispute.id, "resolution": resolution},
    )
    await email_service.notify_user(
        session,
        user_id=dispute.raised_by_id,
        template=email_service.DISPUTE_RESOLVED,
        context={
            "dispute_id": dispute.id,
            "resolution": resolution,
            "refund_amount": dispute.refund_amount,
        },
    )

    return dispute
