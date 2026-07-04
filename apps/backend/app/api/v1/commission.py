"""FEAT-027 -- Commission Rate Configuration endpoints.

Admin-only write access; Staff (and Admin) may read. Every change writes
an immutable AuditLogEntry as part of the same action (AGENTS.md Behavior
Rules: "Every sensitive Admin Web Console action ... writes an immutable
AuditLogEntry before/as part of the action taking effect").
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, UserRole, require_roles
from app.models.ops import AuditLogEntry
from app.schemas.transaction import (
    CommissionRateHistoryResponse,
    CommissionRateRequest,
    CommissionRateResponse,
)
from app.services.commission_service import get_rate_history, set_commission_rate

router = APIRouter()

VALID_TRANSACTION_TYPES = ("shortlet_booking", "lease_deposit", "sale_reservation")


def _to_response(config) -> CommissionRateResponse:
    return CommissionRateResponse(
        id=config.id,
        transaction_type=config.transaction_type,
        rate_percentage=config.rate_percentage,
        set_by_id=config.set_by_id,
        effective_from=config.effective_from,
        created_at=config.created_at,
    )


@router.get("/{transaction_type}", response_model=CommissionRateHistoryResponse)
async def get_commission_rate(
    transaction_type: str,
    current_user: CurrentUser = Depends(
        require_roles(UserRole.DEDUKE_STAFF, UserRole.DEDUKE_ADMIN)
    ),
    session: AsyncSession = Depends(get_session),
) -> CommissionRateHistoryResponse:
    """Staff: read-only. Admin: read (write is via POST below)."""
    if transaction_type not in VALID_TRANSACTION_TYPES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"transaction_type must be one of {VALID_TRANSACTION_TYPES}",
        )
    history = await get_rate_history(session, transaction_type)
    return CommissionRateHistoryResponse(
        transaction_type=transaction_type,
        current=_to_response(history[0]) if history else None,
        history=[_to_response(h) for h in history],
    )


@router.post("", response_model=CommissionRateResponse, status_code=status.HTTP_201_CREATED)
async def set_commission_rate_endpoint(
    body: CommissionRateRequest,
    current_user: CurrentUser = Depends(require_roles(UserRole.DEDUKE_ADMIN)),
    session: AsyncSession = Depends(get_session),
) -> CommissionRateResponse:
    """Admin-only. Validated 0-100%; retains full history (append-only);
    effective only for transactions initiated after this call, since
    `commission_service.get_effective_rate` looks up by `effective_from`
    and existing Transactions have already snapshotted their own rate."""
    if body.transaction_type not in VALID_TRANSACTION_TYPES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"transaction_type must be one of {VALID_TRANSACTION_TYPES}",
        )
    try:
        async with session.begin():
            config = await set_commission_rate(
                session,
                transaction_type=body.transaction_type,
                rate_percentage=body.rate_percentage,
                set_by_id=current_user.user_id,
            )
            session.add(
                AuditLogEntry(
                    actor_id=current_user.user_id,
                    action_type="commission_rate_changed",
                    target_type="CommissionRateConfig",
                    target_id=config.id,
                    notes=f"{body.transaction_type} -> {body.rate_percentage}%",
                )
            )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)
        ) from exc

    return _to_response(config)
