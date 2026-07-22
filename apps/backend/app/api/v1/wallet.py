"""FEAT-043 (Admin-Only Escrow Release) + FEAT-044 (Host/Agency Virtual
Wallet) + FEAT-045 (Payout Settings & Withdrawal) endpoints.

Route groups:
  - /wallet/admin/releasable, /wallet/admin/{transaction_id}/release --
    Admin-only (FEAT-043).
  - /wallet, /wallet/transactions -- the caller's own Wallet (FEAT-044).
  - /wallet/payout-settings -- the caller's own bank account (FEAT-045).
  - /wallet/withdrawals -- the caller's own withdrawal requests (FEAT-045).

"Own" wallet/payout-settings/withdrawals always resolve to the caller's
payee ROOT (an independent host's own user id, or an agency's root
account) via `agency_service`'s existing resolution -- never a raw
`current_user.user_id` for an invited agency team member, matching how
`Transaction.payee_id` itself is resolved at booking time.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, UserRole, get_current_user, require_roles
from app.models.ops import AuditLogEntry
from app.schemas.wallet import (
    BankOptionOut,
    PayoutSettingsRequest,
    PayoutSettingsResponse,
    ReleasableTransactionOut,
    ReleaseFundsResponse,
    WalletOut,
    WalletTransactionListResponse,
    WalletTransactionOut,
    WithdrawalRequestBody,
    WithdrawalResponse,
)
from app.services import payment_service, wallet_service, withdrawal_service
from app.services.agency_service import resolve_agency_id_for_listing
from app.services.payout_settings_service import PayoutSettingsError, save_payout_settings
from app.services.payout_settings_service import get_payout_settings as get_payout_settings_row
from app.services.wallet_service import WalletError
from app.services.withdrawal_service import WithdrawalError

router = APIRouter()


async def _resolve_owner_root_id(session: AsyncSession, current_user: CurrentUser) -> str:
    """The wallet/payout-settings/withdrawal owner for the caller --
    their agency root if they're an agency team member, otherwise their
    own user id (matches Transaction.payee_id's own resolution).

    Bug fix: this must always be called AFTER `async with session.begin():`
    has already been entered (never before it) -- it runs a `session.get`
    internally, and AsyncSession autobegins a transaction on its first
    operation. Calling this before `session.begin()` left the session
    already mid-transaction by the time `session.begin()` ran, which
    SQLAlchemy rejects with "A transaction is already begun on this
    Session." Every call site below now resolves the owner id INSIDE the
    `async with session.begin():` block for exactly this reason.
    """
    agency_id = await resolve_agency_id_for_listing(session, current_user)
    return agency_id or current_user.user_id


# -- FEAT-043: Admin-Only Escrow Release ---------------------------------


@router.get("/admin/releasable", response_model=list[ReleasableTransactionOut])
async def list_releasable_transactions(
    status_filter: str = "pending",
    listing_id: str | None = None,
    current_user: CurrentUser = Depends(require_roles(UserRole.DEDUKE_ADMIN)),
    session: AsyncSession = Depends(get_session),
) -> list[ReleasableTransactionOut]:
    """`status_filter`: 'pending' (default, still-escrowed -- the
    to-do queue), 'released' (already-released -- a persisted log, not
    removed from view once acted on), or 'all' (both). `listing_id`
    additionally scopes to one property -- backs the property detail
    page's "View release history" deep link."""
    try:
        rows = await wallet_service.list_release_queue(
            session, status_filter=status_filter, listing_id=listing_id
        )
    except WalletError as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)) from exc
    return [
        ReleasableTransactionOut(
            transaction_id=t.id,
            listing_id=t.listing_id,
            payer_id=t.payer_id,
            payee_id=t.payee_id,
            transaction_type=t.transaction_type,
            gross_amount=t.gross_amount,
            commission_amount=t.commission_amount,
            net_payout_amount=t.net_payout_amount,
            paid_at=t.paid_at,
            status=t.status,
            released_at=t.released_at,
            released_by_admin_id=t.released_by_admin_id,
            has_open_dispute=has_open_dispute,
        )
        for t, has_open_dispute in rows
    ]


@router.post("/admin/{transaction_id}/release", response_model=ReleaseFundsResponse)
async def release_transaction(
    transaction_id: str,
    current_user: CurrentUser = Depends(require_roles(UserRole.DEDUKE_ADMIN)),
    session: AsyncSession = Depends(get_session),
) -> ReleaseFundsResponse:
    """Admin-only per FEAT-043 AC. Writes an AuditLogEntry as part of the
    same atomic operation (AGENTS.md Behavior Rules) -- see
    wallet_service.release_transaction, which does the actual audit-log
    write inside the same DB transaction as the status flip + wallet
    credit."""
    try:
        async with session.begin():
            txn = await wallet_service.release_transaction(
                session, transaction_id=transaction_id, admin_id=current_user.user_id
            )
    except WalletError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    # Notification fires only after the release has actually committed
    # (see wallet_service.notify_release's own docstring for why this is
    # split out of the atomic block above).
    await wallet_service.notify_release(session, txn=txn)

    return ReleaseFundsResponse(
        transaction_id=txn.id,
        status=txn.status,
        released_at=txn.released_at,
        released_by_admin_id=txn.released_by_admin_id,
        net_payout_amount=txn.net_payout_amount,
    )


# -- FEAT-044: Host/Agency Virtual Wallet --------------------------------


@router.get("", response_model=WalletOut)
async def get_my_wallet(
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> WalletOut:
    async with session.begin():
        owner_id = await _resolve_owner_root_id(session, current_user)
        wallet = await wallet_service.ensure_wallet(session, owner_id=owner_id)
    return WalletOut(
        id=wallet.id,
        owner_id=wallet.owner_id,
        balance=wallet.balance,
        currency=wallet.currency,
        updated_at=wallet.updated_at,
    )


@router.get("/transactions", response_model=WalletTransactionListResponse)
async def get_my_wallet_transactions(
    before: str | None = None,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> WalletTransactionListResponse:
    async with session.begin():
        owner_id = await _resolve_owner_root_id(session, current_user)
        wallet = await wallet_service.ensure_wallet(session, owner_id=owner_id)
        entries = await wallet_service.get_wallet_transactions(
            session, wallet_id=wallet.id, before_id=before
        )
    items = [
        WalletTransactionOut(
            id=e.id,
            direction=e.direction,
            amount=e.amount,
            source_type=e.source_type,
            source_id=e.source_id,
            balance_after=e.balance_after,
            notes=e.notes,
            created_at=e.created_at,
        )
        for e in entries
    ]
    return WalletTransactionListResponse(
        items=items, next_cursor=items[-1].id if len(items) == 50 else None
    )


# -- FEAT-045: Payout Settings --------------------------------------------


@router.get("/banks", response_model=list[BankOptionOut])
async def list_banks(
    current_user: CurrentUser = Depends(get_current_user),
) -> list[BankOptionOut]:
    """Backs the Payout Settings bank picker -- see
    payment_service.list_banks's own docstring for why this exists rather
    than a freehand bank name/code field."""
    try:
        banks = await payment_service.list_banks()
    except payment_service.PaystackNotConfiguredError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)
        ) from exc
    return [BankOptionOut(name=b.name, code=b.code) for b in banks]


@router.get("/payout-settings", response_model=PayoutSettingsResponse | None)
async def get_my_payout_settings(
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> PayoutSettingsResponse | None:
    owner_id = await _resolve_owner_root_id(session, current_user)
    payout = await get_payout_settings_row(session, owner_id=owner_id)
    if payout is None:
        return None
    return PayoutSettingsResponse(
        id=payout.id,
        account_number=payout.account_number,
        bank_code=payout.bank_code,
        bank_name=payout.bank_name,
        account_holder_name=payout.account_holder_name,
        verification_status=payout.verification_status,
        updated_at=payout.updated_at,
    )


@router.put("/payout-settings", response_model=PayoutSettingsResponse)
async def put_my_payout_settings(
    body: PayoutSettingsRequest,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> PayoutSettingsResponse:
    try:
        async with session.begin():
            owner_id = await _resolve_owner_root_id(session, current_user)
            payout = await save_payout_settings(
                session,
                owner_id=owner_id,
                account_number=body.account_number,
                bank_code=body.bank_code,
                bank_name=body.bank_name,
            )
            session.add(
                AuditLogEntry(
                    actor_id=current_user.user_id,
                    action_type="payout_settings_saved",
                    target_type="PayoutSettings",
                    target_id=payout.id,
                    notes=f"bank_code={body.bank_code}",
                )
            )
    except PayoutSettingsError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    return PayoutSettingsResponse(
        id=payout.id,
        account_number=payout.account_number,
        bank_code=payout.bank_code,
        bank_name=payout.bank_name,
        account_holder_name=payout.account_holder_name,
        verification_status=payout.verification_status,
        updated_at=payout.updated_at,
    )


# -- FEAT-045: Withdrawal --------------------------------------------------


@router.post("/withdrawals", response_model=WithdrawalResponse, status_code=status.HTTP_201_CREATED)
async def request_withdrawal(
    body: WithdrawalRequestBody,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> WithdrawalResponse:
    try:
        async with session.begin():
            owner_id = await _resolve_owner_root_id(session, current_user)
            wallet = await wallet_service.ensure_wallet(session, owner_id=owner_id)
            withdrawal = await withdrawal_service.request_withdrawal(
                session,
                wallet=wallet,
                amount=body.amount,
                requested_by_id=current_user.user_id,
            )
    except WithdrawalError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    return WithdrawalResponse(
        id=withdrawal.id,
        wallet_id=withdrawal.wallet_id,
        amount=withdrawal.amount,
        status=withdrawal.status,
        requested_at=withdrawal.requested_at,
        paystack_transfer_reference=withdrawal.paystack_transfer_reference,
        fulfilled_at=withdrawal.fulfilled_at,
        failure_reason=withdrawal.failure_reason,
    )


@router.get("/withdrawals", response_model=list[WithdrawalResponse])
async def list_my_withdrawals(
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[WithdrawalResponse]:
    async with session.begin():
        owner_id = await _resolve_owner_root_id(session, current_user)
        wallet = await wallet_service.ensure_wallet(session, owner_id=owner_id)
        withdrawals = await withdrawal_service.list_withdrawals(session, wallet_id=wallet.id)
    return [
        WithdrawalResponse(
            id=w.id,
            wallet_id=w.wallet_id,
            amount=w.amount,
            status=w.status,
            requested_at=w.requested_at,
            paystack_transfer_reference=w.paystack_transfer_reference,
            fulfilled_at=w.fulfilled_at,
            failure_reason=w.failure_reason,
        )
        for w in withdrawals
    ]
