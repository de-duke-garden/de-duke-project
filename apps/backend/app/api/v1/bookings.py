"""FEAT-032 -- Booking Hold & Confirm-Before-Pay endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, get_current_user
from app.schemas.booking import BookingHoldResponse, ConfirmBookingRequest
from app.services import analytics_service, push_service
from app.services.booking_service import (
    InvalidBookingDatesError,
    ListingNotFoundError,
    ListingUnavailableError,
    confirm_booking,
    get_transaction_for_owner,
)
from app.services.email_service import BOOKING_HOLD_CONFIRMED, notify_user

router = APIRouter()


@router.post("/confirm", response_model=BookingHoldResponse, status_code=status.HTTP_201_CREATED)
async def confirm_booking_endpoint(
    body: ConfirmBookingRequest,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> BookingHoldResponse:
    """Creates a `held` Transaction, enforcing the double-booking invariant
    via DB-level row locking in `booking_service.confirm_booking` (SELECT
    ... FOR UPDATE on the listing row + overlapping-transaction rows).
    """
    try:
        async with session.begin():
            txn = await confirm_booking(
                session,
                payer_id=current_user.user_id,
                listing_id=body.listing_id,
                check_in_date=body.check_in_date,
                check_out_date=body.check_out_date,
            )
    except ListingNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except ListingUnavailableError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    except InvalidBookingDatesError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)
        ) from exc

    notification_context = {
        "transaction_id": txn.id,
        "hold_expires_at": txn.hold_expires_at.isoformat() if txn.hold_expires_at else None,
    }
    await notify_user(
        session,
        user_id=current_user.user_id,
        template=BOOKING_HOLD_CONFIRMED,
        context=notification_context,
    )
    # FEAT-022: push shares this trigger event with email (architecture.md
    # "Notification Service (Push & Email)": "Push and email share the
    # same triggering events but serve different needs"). Additive, not a
    # replacement -- both channels fire independently and each respects
    # its own per-category preference.
    await push_service.notify_user(
        session,
        user_id=current_user.user_id,
        template=push_service.BOOKING_HOLD_CONFIRMED,
        context=notification_context,
    )
    await analytics_service.track_event(
        event_name=analytics_service.BOOKING_INITIATED,
        user_id=current_user.user_id,
        properties={
            "listing_id": txn.listing_id,
            "transaction_id": txn.id,
            "gross_amount": txn.gross_amount,
        },
    )

    return BookingHoldResponse(
        transaction_id=txn.id,
        listing_id=txn.listing_id,
        status=txn.status,
        gross_amount=txn.gross_amount,
        hold_expires_at=txn.hold_expires_at,
        possession_period_start_date=txn.possession_period_start_date,
        possession_period_end_date=txn.possession_period_end_date,
    )


@router.get("/{transaction_id}", response_model=BookingHoldResponse)
async def get_booking_hold(
    transaction_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> BookingHoldResponse:
    """Used by the mobile confirm-booking/checkout screens to poll the live
    hold countdown and detect the Hold Expired state."""
    txn = await get_transaction_for_owner(session, transaction_id, current_user.user_id)
    if txn is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Booking not found")
    return BookingHoldResponse(
        transaction_id=txn.id,
        listing_id=txn.listing_id,
        status=txn.status,
        gross_amount=txn.gross_amount,
        hold_expires_at=txn.hold_expires_at,
        possession_period_start_date=txn.possession_period_start_date,
        possession_period_end_date=txn.possession_period_end_date,
    )
