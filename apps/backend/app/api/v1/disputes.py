"""Dispute & Refund Management endpoints -- FEAT-026.

POST / is mobile-facing (any authenticated user raising a dispute against
their own transaction, from Transaction History). Every other endpoint
requires DEDUKE_STAFF or DEDUKE_ADMIN, enforced server-side via
`require_roles` (never hidden via client UI alone), backing screens.md
Screen 24 (Admin: Dispute & Refund Management).
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, UserRole, get_current_user, require_roles
from app.schemas.dispute import (
    DisputeAssignRequest,
    DisputeCreateRequest,
    DisputeDetailOut,
    DisputeListItemOut,
    DisputeOut,
    DisputeResolveRequest,
)
from app.services import dispute_service

router = APIRouter()

staff_or_admin = require_roles(UserRole.DEDUKE_STAFF, UserRole.DEDUKE_ADMIN)


@router.post("", response_model=DisputeOut, status_code=status.HTTP_201_CREATED)
async def raise_dispute(
    payload: DisputeCreateRequest,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> DisputeOut:
    try:
        dispute = await dispute_service.create_dispute(
            session,
            transaction_id=payload.transaction_id,
            raised_by_id=current_user.user_id,
            reason=payload.reason,
            description=payload.description,
        )
    except dispute_service.DisputeError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    return DisputeOut(
        id=dispute.id,
        transaction_id=dispute.transaction_id,
        reason=dispute.reason,
        status=dispute.status,
        created_at=dispute.created_at,
    )


async def _to_list_item(session: AsyncSession, dispute) -> DisputeListItemOut:  # noqa: ANN001
    transaction = await dispute_service.get_transaction_or_none(session, dispute.transaction_id)
    return DisputeListItemOut(
        id=dispute.id,
        transaction_id=dispute.transaction_id,
        listing_id=transaction.listing_id if transaction is not None else None,
        raised_by_id=dispute.raised_by_id,
        raised_by_name=await dispute_service.get_user_name_or_unknown(
            session, dispute.raised_by_id
        )
        or "Unknown",
        reason=dispute.reason,
        status=dispute.status,
        assigned_staff_id=dispute.assigned_staff_id,
        assigned_staff_name=await dispute_service.get_user_name_or_unknown(
            session, dispute.assigned_staff_id
        ),
        created_at=dispute.created_at,
    )


@router.get("", response_model=list[DisputeListItemOut])
async def list_disputes(
    status_filter: str | None = None,
    listing_id: str | None = None,
    _current_user: CurrentUser = Depends(staff_or_admin),
    session: AsyncSession = Depends(get_session),
) -> list[DisputeListItemOut]:
    disputes = await dispute_service.list_disputes(
        session, status_filter=status_filter, listing_id=listing_id
    )
    return [await _to_list_item(session, d) for d in disputes]


@router.get("/{dispute_id}", response_model=DisputeDetailOut)
async def get_dispute_detail(
    dispute_id: str,
    _current_user: CurrentUser = Depends(staff_or_admin),
    session: AsyncSession = Depends(get_session),
) -> DisputeDetailOut:
    dispute = await dispute_service.get_dispute(session, dispute_id)
    if dispute is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dispute not found.")

    transaction = await dispute_service.get_transaction_or_none(
        session, dispute.transaction_id
    )
    if transaction is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Linked transaction not found."
        )

    return DisputeDetailOut(
        id=dispute.id,
        transaction_id=dispute.transaction_id,
        raised_by_id=dispute.raised_by_id,
        raised_by_name=await dispute_service.get_user_name_or_unknown(
            session, dispute.raised_by_id
        )
        or "Unknown",
        reason=dispute.reason,
        status=dispute.status,
        assigned_staff_id=dispute.assigned_staff_id,
        assigned_staff_name=await dispute_service.get_user_name_or_unknown(
            session, dispute.assigned_staff_id
        ),
        created_at=dispute.created_at,
        description=dispute.description,
        resolution_notes=dispute.resolution_notes,
        refund_amount=dispute.refund_amount,
        resolved_at=dispute.resolved_at,
        listing_id=transaction.listing_id,
        transaction_gross_amount=transaction.gross_amount,
        transaction_status=transaction.status,
    )


@router.patch("/{dispute_id}/assign", response_model=DisputeListItemOut)
async def assign_dispute(
    dispute_id: str,
    payload: DisputeAssignRequest,
    current_user: CurrentUser = Depends(staff_or_admin),
    session: AsyncSession = Depends(get_session),
) -> DisputeListItemOut:
    dispute = await dispute_service.get_dispute(session, dispute_id)
    if dispute is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dispute not found.")

    try:
        dispute = await dispute_service.assign_dispute(
            session,
            dispute=dispute,
            staff_id=payload.staff_id,
            actor_id=current_user.user_id,
        )
    except dispute_service.DisputeError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    return await _to_list_item(session, dispute)


@router.patch("/{dispute_id}/resolve", response_model=DisputeDetailOut)
async def resolve_dispute(
    dispute_id: str,
    payload: DisputeResolveRequest,
    current_user: CurrentUser = Depends(staff_or_admin),
    session: AsyncSession = Depends(get_session),
) -> DisputeDetailOut:
    dispute = await dispute_service.get_dispute(session, dispute_id)
    if dispute is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Dispute not found.")

    try:
        dispute = await dispute_service.resolve_dispute(
            session,
            dispute=dispute,
            resolution=payload.resolution,
            resolution_notes=payload.resolution_notes,
            refund_amount=payload.refund_amount,
            actor_id=current_user.user_id,
        )
    except dispute_service.DisputeError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    transaction = await dispute_service.get_transaction_or_none(
        session, dispute.transaction_id
    )
    assert transaction is not None  # validated inside resolve_dispute already

    return DisputeDetailOut(
        id=dispute.id,
        transaction_id=dispute.transaction_id,
        raised_by_id=dispute.raised_by_id,
        raised_by_name=await dispute_service.get_user_name_or_unknown(
            session, dispute.raised_by_id
        )
        or "Unknown",
        reason=dispute.reason,
        status=dispute.status,
        assigned_staff_id=dispute.assigned_staff_id,
        assigned_staff_name=await dispute_service.get_user_name_or_unknown(
            session, dispute.assigned_staff_id
        ),
        created_at=dispute.created_at,
        description=dispute.description,
        resolution_notes=dispute.resolution_notes,
        refund_amount=dispute.refund_amount,
        resolved_at=dispute.resolved_at,
        listing_id=transaction.listing_id,
        transaction_gross_amount=transaction.gross_amount,
        transaction_status=transaction.status,
    )
