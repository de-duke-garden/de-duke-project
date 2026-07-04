"""FEAT-013/014 -- Transaction history + commission breakdown, and FEAT-024
receipt access."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, get_current_user
from app.models.transaction import Receipt, Transaction
from app.schemas.transaction import (
    CommissionBreakdown,
    TransactionDetail,
    TransactionListResponse,
    TransactionSummary,
)

router = APIRouter()


@router.get("", response_model=TransactionListResponse)
async def list_transactions(
    cursor: str | None = None,
    limit: int = 20,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TransactionListResponse:
    """Cursor-based (keyset) pagination on `id`, per AGENTS.md -- never
    offset/page-number pagination."""
    limit = max(1, min(limit, 100))
    query = (
        select(Transaction)
        .where(
            (Transaction.payer_id == current_user.user_id)
            | (Transaction.payee_id == current_user.user_id)
        )
        .order_by(Transaction.id)
        .limit(limit + 1)
    )
    if cursor:
        query = query.where(Transaction.id > cursor)

    result = await session.execute(query)
    rows = list(result.scalars().all())
    next_cursor = rows[limit].id if len(rows) > limit else None
    rows = rows[:limit]

    return TransactionListResponse(
        items=[
            TransactionSummary(
                id=t.id,
                listing_id=t.listing_id,
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
    receipt_result = await session.execute(
        select(Receipt).where(Receipt.transaction_id == txn.id)
    )
    receipt = receipt_result.scalar_one_or_none()
    return TransactionDetail(
        id=txn.id,
        listing_id=txn.listing_id,
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
    )


@router.get("/{transaction_id}/commission", response_model=CommissionBreakdown)
async def get_commission_breakdown(
    transaction_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> CommissionBreakdown:
    """Exposes the commission breakdown to both payer and payee (FEAT-014)."""
    txn = await _get_owned_transaction(session, transaction_id, current_user.user_id)
    rate_percentage = (
        (txn.commission_amount / txn.gross_amount * 100.0) if txn.gross_amount else 0.0
    )
    return CommissionBreakdown(
        transaction_id=txn.id,
        transaction_type=txn.transaction_type,
        rate_percentage=round(rate_percentage, 2),
        gross_amount=txn.gross_amount,
        commission_amount=txn.commission_amount,
        net_payout_amount=txn.net_payout_amount,
    )
