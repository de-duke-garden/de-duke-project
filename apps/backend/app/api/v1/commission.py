"""FEAT-027 -- Commission Rate Configuration endpoints.

Two-sided commission model (product decision): `buyer_fee` and
`owner_commission` are two independent, independently-configurable rates
per transaction_type -- see commission_service.py's module docstring.

Admin-only write access; Staff (and Admin) may read the full
history/audit-trail shape. Every change writes an immutable AuditLogEntry
as part of the same action (AGENTS.md Behavior Rules: "Every sensitive
Admin Web Console action ... writes an immutable AuditLogEntry before/as
part of the action taking effect").

The `/current` endpoint below is separate and deliberately open to any
authenticated user (not Staff/Admin-gated) -- a guest needs to know the
current `buyer_fee` rate before confirming a booking (so the price they
see matches what's actually charged), and a payee needs to know the
current `owner_commission` rate. Neither is sensitive information (it's
already implied by every receipt), but the full history/set_by_id
audit-trail shape stays Staff/Admin-only below.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, UserRole, get_current_user, require_roles
from app.models.ops import AuditLogEntry
from app.schemas.transaction import (
    CommissionRateHistoryResponse,
    CommissionRateRequest,
    CommissionRateResponse,
)
from app.services.commission_service import (
    FEE_TYPES,
    get_effective_rate,
    get_rate_history,
    set_commission_rate,
)

router = APIRouter()

VALID_TRANSACTION_TYPES = ("shortlet_booking", "lease_deposit", "sale_reservation")


def _validate_transaction_type(transaction_type: str) -> None:
    if transaction_type not in VALID_TRANSACTION_TYPES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"transaction_type must be one of {VALID_TRANSACTION_TYPES}",
        )


def _validate_fee_type(fee_type: str) -> None:
    if fee_type not in FEE_TYPES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"fee_type must be one of {FEE_TYPES}",
        )


def _to_response(config) -> CommissionRateResponse:
    return CommissionRateResponse(
        id=config.id,
        transaction_type=config.transaction_type,
        fee_type=config.fee_type,
        rate_percentage=config.rate_percentage,
        set_by_id=config.set_by_id,
        effective_from=config.effective_from,
        created_at=config.created_at,
    )


@router.get("/{transaction_type}/{fee_type}/current")
async def get_current_commission_rate(
    transaction_type: str,
    fee_type: str,
    _current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> dict[str, str | float]:
    """Open to any authenticated user -- see module docstring. Just the
    single number a booking/payout screen needs, no history/audit fields."""
    _validate_transaction_type(transaction_type)
    _validate_fee_type(fee_type)
    rate_percentage = await get_effective_rate(session, transaction_type, fee_type)
    return {
        "transaction_type": transaction_type,
        "fee_type": fee_type,
        "rate_percentage": rate_percentage,
    }


@router.get("/{transaction_type}/{fee_type}", response_model=CommissionRateHistoryResponse)
async def get_commission_rate(
    transaction_type: str,
    fee_type: str,
    current_user: CurrentUser = Depends(
        require_roles(UserRole.DEDUKE_STAFF, UserRole.DEDUKE_ADMIN)
    ),
    session: AsyncSession = Depends(get_session),
) -> CommissionRateHistoryResponse:
    """Staff: read-only. Admin: read (write is via POST below)."""
    _validate_transaction_type(transaction_type)
    _validate_fee_type(fee_type)
    history = await get_rate_history(session, transaction_type, fee_type)
    return CommissionRateHistoryResponse(
        transaction_type=transaction_type,
        fee_type=fee_type,
        current=_to_response(history[0]) if history else None,
        history=[_to_response(h) for h in history],
    )


@router.post("", response_model=CommissionRateResponse, status_code=status.HTTP_201_CREATED)
async def set_commission_rate_endpoint(
    body: CommissionRateRequest,
    current_user: CurrentUser = Depends(require_roles(UserRole.DEDUKE_ADMIN)),
    session: AsyncSession = Depends(get_session),
) -> CommissionRateResponse:
    """Admin-only. Validated 0-100%; retains full history (append-only) per
    (transaction_type, fee_type) pair; effective only for transactions
    initiated after this call, since `commission_service.get_effective_rate`
    looks up by `effective_from` and existing Transactions have already
    snapshotted their own rates at hold-creation time."""
    _validate_transaction_type(body.transaction_type)
    _validate_fee_type(body.fee_type)
    try:
        async with session.begin():
            config = await set_commission_rate(
                session,
                transaction_type=body.transaction_type,
                fee_type=body.fee_type,
                rate_percentage=body.rate_percentage,
                set_by_id=current_user.user_id,
            )
            session.add(
                AuditLogEntry(
                    actor_id=current_user.user_id,
                    action_type="commission_rate_changed",
                    target_type="CommissionRateConfig",
                    target_id=config.id,
                    notes=f"{body.transaction_type}/{body.fee_type} -> {body.rate_percentage}%",
                )
            )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)
        ) from exc

    return _to_response(config)
