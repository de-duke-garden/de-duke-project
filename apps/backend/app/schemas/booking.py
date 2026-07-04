"""Request/response contracts for FEAT-032 (Booking Hold & Confirm-Before-Pay).

Kept separate from app/models/transaction.py per AGENTS.md -- ORM models are
never reused as API schemas.
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field, field_validator


class ConfirmBookingRequest(BaseModel):
    listing_id: str
    # Required only for shortlet listings; ignored for commercial listings
    # (possession dates are derived from CommercialListing.possession_period_days).
    check_in_date: datetime | None = None
    check_out_date: datetime | None = None

    @field_validator("check_out_date")
    @classmethod
    def _checkout_after_checkin(cls, v: datetime | None, info) -> datetime | None:
        check_in = info.data.get("check_in_date")
        if v is not None and check_in is not None and v <= check_in:
            raise ValueError("check_out_date must be after check_in_date")
        return v


class BookingHoldResponse(BaseModel):
    transaction_id: str
    listing_id: str
    status: str
    gross_amount: float
    hold_expires_at: datetime
    possession_period_start_date: datetime | None
    possession_period_end_date: datetime | None


class HoldExpiredError(BaseModel):
    detail: str = Field(default="Your booking hold has expired. Please start again.")
