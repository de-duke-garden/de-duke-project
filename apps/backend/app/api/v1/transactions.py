"""FEAT-013/014 -- Transaction history + commission breakdown, and FEAT-024
receipt access."""

from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, get_current_user
from app.models.listing import Listing
from app.models.transaction import Receipt, Transaction
from app.schemas.transaction import (
    CommissionBreakdown,
    TransactionDetail,
    TransactionListResponse,
    TransactionSummary,
)
from app.services.receipt_service import ensure_receipt

router = APIRouter()

# FEAT-015 AC: "Receipts are accessible even if the underlying listing is
# later removed" -- a transaction must never fail to load just because its
# listing is gone, so a missing title degrades to this placeholder rather
# than a 404/500 on the whole transaction.
_DELETED_LISTING_TITLE = "Listing no longer available"


async def _listing_titles(session: AsyncSession, listing_ids: set[str]) -> dict[str, str]:
    """Batched (one query for the whole page, not N+1 per transaction row)
    -- same pattern listing_service.list_host_listings/search_service's own
    primary-image batching already use."""
    if not listing_ids:
        return {}
    result = await session.execute(
        select(Listing.id, Listing.title).where(Listing.id.in_(listing_ids))
    )
    return dict(result.all())


@router.get("", response_model=TransactionListResponse)
async def list_transactions(
    cursor: str | None = None,
    limit: int = 20,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TransactionListResponse:
    """Cursor-based (keyset) pagination, per AGENTS.md -- never
    offset/page-number pagination.

    Bug fix: previously ordered (and keyset-paginated) by `Transaction.id`
    alone -- a random per-row UUID with no chronological relationship to
    when the transaction was created, so Transaction History effectively
    showed transactions in an arbitrary order instead of the expected
    most-recent-first. Now orders by `created_at DESC`, with `id DESC` as
    a tiebreaker only for the rare case of two transactions sharing the
    exact same timestamp (keyset pagination needs a fully-deterministic
    order, not just "mostly by date"). The cursor is therefore now a
    composite `"<created_at isoformat>_<id>"` rather than a bare id --
    opaque to the client either way, just carried through verbatim.
    """
    limit = max(1, min(limit, 100))
    query = (
        select(Transaction)
        .where(
            (Transaction.payer_id == current_user.user_id)
            | (Transaction.payee_id == current_user.user_id)
        )
        .order_by(Transaction.created_at.desc(), Transaction.id.desc())
        .limit(limit + 1)
    )
    if cursor:
        cursor_created_at_raw, _, cursor_id = cursor.rpartition("_")
        if not cursor_created_at_raw:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid cursor"
            )
        try:
            cursor_created_at = datetime.fromisoformat(cursor_created_at_raw)
        except ValueError as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid cursor"
            ) from exc
        query = query.where(
            or_(
                Transaction.created_at < cursor_created_at,
                and_(
                    Transaction.created_at == cursor_created_at,
                    Transaction.id < cursor_id,
                ),
            )
        )

    result = await session.execute(query)
    rows = list(result.scalars().all())
    next_cursor = (
        f"{rows[limit].created_at.isoformat()}_{rows[limit].id}"
        if len(rows) > limit
        else None
    )
    rows = rows[:limit]

    titles = await _listing_titles(session, {t.listing_id for t in rows})

    return TransactionListResponse(
        items=[
            TransactionSummary(
                id=t.id,
                listing_id=t.listing_id,
                listing_title=titles.get(t.listing_id, _DELETED_LISTING_TITLE),
                transaction_type=t.transaction_type,
                status=t.status,
                gross_amount=t.gross_amount,
                commission_amount=t.commission_amount,
                net_payout_amount=t.net_payout_amount,
                possession_period_start_date=t.possession_period_start_date,
                possession_period_end_date=t.possession_period_end_date,
                created_at=t.created_at,
            )
            for t in rows
        ],
        next_cursor=next_cursor,
    )


async def _get_owned_transaction(
    session: AsyncSession, transaction_id: str, user_id: str
) -> Transaction:
    result = await session.execute(select(Transaction).where(Transaction.id == transaction_id))
    txn = result.scalar_one_or_none()
    if txn is None or (txn.payer_id != user_id and txn.payee_id != user_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transaction not found")
    return txn


@router.get("/{transaction_id}", response_model=TransactionDetail)
async def get_transaction(
    transaction_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TransactionDetail:
    txn = await _get_owned_transaction(session, transaction_id, current_user.user_id)
    receipt_result = await session.execute(select(Receipt).where(Receipt.transaction_id == txn.id))
    receipt = receipt_result.scalar_one_or_none()
    # Lazy fallback: covers any transaction that reached held/succeeded
    # without going through bookings.py's/the webhook handler's own
    # `ensure_receipt` calls (e.g. rows created before this feature
    # existed), and self-heals a receipt that still describes a hold for a
    # transaction that has since succeeded. No-ops (single indexed lookup)
    # once a transaction's receipt is already current.
    receipt = await ensure_receipt(session, txn) or receipt
    titles = await _listing_titles(session, {txn.listing_id})
    return TransactionDetail(
        id=txn.id,
        listing_id=txn.listing_id,
        listing_title=titles.get(txn.listing_id, _DELETED_LISTING_TITLE),
        transaction_type=txn.transaction_type,
        status=txn.status,
        gross_amount=txn.gross_amount,
        commission_amount=txn.commission_amount,
        net_payout_amount=txn.net_payout_amount,
        possession_period_start_date=txn.possession_period_start_date,
        possession_period_end_date=txn.possession_period_end_date,
        created_at=txn.created_at,
        payer_id=txn.payer_id,
        payee_id=txn.payee_id,
        payment_processor_reference=txn.payment_processor_reference,
        paid_at=txn.paid_at,
        hold_expires_at=txn.hold_expires_at,
        receipt_url=receipt.pdf_url if receipt else None,
        listing_price=txn.listing_price,
        buyer_fee_amount=txn.buyer_fee_amount,
        owner_commission_amount=txn.owner_commission_amount,
    )


@router.get("/{transaction_id}/commission", response_model=CommissionBreakdown)
async def get_commission_breakdown(
    transaction_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> CommissionBreakdown:
    """Exposes the full two-sided commission breakdown to both payer and
    payee (FEAT-014). `listing_price`/`buyer_fee_amount`/
    `owner_commission_amount` are null only for legacy transactions
    predating the two-sided model (migration c9d0e1f2a3b4) -- those fall
    back to treating the transaction's entire historical commission as an
    owner-side deduction with a 0% buyer fee, matching that migration's
    own backfill so this endpoint stays consistent with what
    TransactionDetail already shows for the same row."""
    txn = await _get_owned_transaction(session, transaction_id, current_user.user_id)
    listing_price = txn.listing_price if txn.listing_price is not None else txn.gross_amount
    buyer_fee_amount = txn.buyer_fee_amount if txn.buyer_fee_amount is not None else 0.0
    owner_commission_amount = (
        txn.owner_commission_amount
        if txn.owner_commission_amount is not None
        else txn.commission_amount
    )
    buyer_fee_percentage = (buyer_fee_amount / listing_price * 100.0) if listing_price else 0.0
    owner_commission_percentage = (
        (owner_commission_amount / listing_price * 100.0) if listing_price else 0.0
    )
    return CommissionBreakdown(
        transaction_id=txn.id,
        transaction_type=txn.transaction_type,
        listing_price=listing_price,
        buyer_fee_amount=buyer_fee_amount,
        buyer_fee_percentage=round(buyer_fee_percentage, 2),
        owner_commission_amount=owner_commission_amount,
        owner_commission_percentage=round(owner_commission_percentage, 2),
        gross_amount=txn.gross_amount,
        commission_amount=txn.commission_amount,
        net_payout_amount=txn.net_payout_amount,
    )
