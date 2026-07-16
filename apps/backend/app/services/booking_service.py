"""FEAT-032 -- Booking Hold & Confirm-Before-Pay business logic.

Double-booking invariant: enforced with real DB-level locking, not an
app-level check-then-write race. We open a `SELECT ... FOR UPDATE` against
the listing's own row set of overlapping, non-terminal transactions inside
a single DB transaction, and re-check the overlap after acquiring the lock,
before inserting the new `held` Transaction row. Postgres row locks on the
matched Transaction rows (plus the listing row itself, which we also lock)
serialize concurrent confirm-booking attempts for the *same* listing so
only one holder ever wins the race for overlapping dates.

NOTE (merge): a separate subagent is building Listings
(app/services/listing_service.py, `is_listing_available(listing_id, dates)`)
in its own worktree. This module implements its own minimal availability
check directly against Transaction rather than importing that function
(it doesn't exist in this worktree). Reconcile the two at merge time --
ideally the Listings version calls into this same locking primitive, or
this service delegates to `is_listing_available` for the read-only check
while keeping the FOR UPDATE lock here for the write path.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models.listing import CommercialListing, Listing, ShortletListing
from app.models.transaction import Transaction

settings = get_settings()

# Transaction statuses that still hold/consume a listing's availability.
NON_TERMINAL_STATUSES = ("held", "pending_payment", "succeeded")


class BookingError(Exception):
    """Base error for booking-service failures."""


class ListingNotFoundError(BookingError):
    pass


class ListingUnavailableError(BookingError):
    pass


class InvalidBookingDatesError(BookingError):
    pass


async def _lock_listing_row(session: AsyncSession, listing_id: str) -> Listing:
    """Acquire a row lock on the listing itself, so concurrent confirm-booking
    calls for the same listing serialize on this single row before we go on
    to inspect/insert Transaction rows for it."""
    result = await session.execute(
        select(Listing).where(Listing.id == listing_id).with_for_update()
    )
    listing = result.scalar_one_or_none()
    if listing is None:
        raise ListingNotFoundError(f"Listing {listing_id} not found")
    return listing


async def _has_overlapping_hold(
    session: AsyncSession,
    listing_id: str,
    start: datetime,
    end: datetime,
) -> bool:
    """Must be called only after `_lock_listing_row` has been awaited in the
    same DB transaction, so this read reflects a serialized view: no other
    transaction can concurrently insert a competing hold for this listing
    until we commit/rollback."""
    result = await session.execute(
        select(Transaction.id)
        .where(Transaction.listing_id == listing_id)
        .where(Transaction.status.in_(NON_TERMINAL_STATUSES))
        .where(Transaction.possession_period_start_date < end)
        .where(Transaction.possession_period_end_date > start)
        .with_for_update()
    )
    return result.first() is not None


async def _compute_possession_period(
    session: AsyncSession,
    listing: Listing,
    check_in_date: datetime | None,
    check_out_date: datetime | None,
) -> tuple[datetime, datetime, float]:
    """Returns (start, end, gross_amount)."""
    if listing.listing_type == "shortlet":
        shortlet = (
            await session.execute(
                select(ShortletListing).where(ShortletListing.listing_id == listing.id)
            )
        ).scalar_one_or_none()
        if shortlet is None:
            raise ListingUnavailableError("Shortlet detail record missing for listing")
        if check_in_date is None or check_out_date is None:
            raise InvalidBookingDatesError(
                "check_in_date and check_out_date are required for shortlet bookings"
            )
        if check_out_date <= check_in_date:
            raise InvalidBookingDatesError("check_out_date must be after check_in_date")
        nights = (check_out_date - check_in_date).days
        if nights < shortlet.minimum_stay_nights:
            raise InvalidBookingDatesError(
                f"Minimum stay is {shortlet.minimum_stay_nights} night(s)"
            )
        if shortlet.maximum_stay_nights is not None and nights > shortlet.maximum_stay_nights:
            raise InvalidBookingDatesError(
                f"Maximum stay is {shortlet.maximum_stay_nights} night(s)"
            )
        gross_amount = nights * shortlet.nightly_price
        return check_in_date, check_out_date, gross_amount

    # commercial: lease or sale_reservation
    commercial = (
        await session.execute(
            select(CommercialListing).where(CommercialListing.listing_id == listing.id)
        )
    ).scalar_one_or_none()
    if commercial is None:
        raise ListingUnavailableError("Commercial detail record missing for listing")

    start = datetime.now(UTC)
    possession_days = commercial.possession_period_days if commercial.deal_type == "lease" else 1
    if commercial.deal_type == "lease" and possession_days is None:
        possession_days = 365  # default per schema.md
    end = start + timedelta(days=possession_days or 1)
    return start, end, commercial.price


def transaction_type_for_listing(listing: Listing, commercial: CommercialListing | None) -> str:
    if listing.listing_type == "shortlet":
        return "shortlet_booking"
    if commercial is not None and commercial.deal_type == "sale":
        return "sale_reservation"
    return "lease_deposit"


async def confirm_booking(
    session: AsyncSession,
    *,
    payer_id: str,
    listing_id: str,
    check_in_date: datetime | None,
    check_out_date: datetime | None,
) -> Transaction:
    """Creates a `held` Transaction for the given listing, enforcing the
    double-booking invariant via row-level locking (see module docstring).

    Caller is responsible for committing the session; on any error the
    caller should roll back.
    """
    listing = await _lock_listing_row(session, listing_id)
    if listing.status != "active":
        raise ListingUnavailableError("Listing is not currently bookable")

    commercial = (
        await session.execute(
            select(CommercialListing).where(CommercialListing.listing_id == listing.id)
        )
    ).scalar_one_or_none()

    start, end, gross_amount = await _compute_possession_period(
        session, listing, check_in_date, check_out_date
    )

    # Re-check overlap now that the listing row (and any competing
    # transactions) are locked -- closes the check-then-write race window.
    if await _has_overlapping_hold(session, listing_id, start, end):
        raise ListingUnavailableError("These dates are no longer available")

    payee_id = listing.agency_id or listing.host_account_id

    txn = Transaction(
        listing_id=listing_id,
        payer_id=payer_id,
        payee_id=payee_id,
        transaction_type=transaction_type_for_listing(listing, commercial),
        gross_amount=gross_amount,
        commission_amount=0.0,
        net_payout_amount=gross_amount,
        status="held",
        hold_expires_at=datetime.now(UTC)
        + timedelta(minutes=settings.booking_hold_duration_minutes),
        possession_period_start_date=start,
        possession_period_end_date=end,
    )
    session.add(txn)
    await session.flush()
    return txn


async def get_transaction_for_owner(
    session: AsyncSession, transaction_id: str, user_id: str
) -> Transaction | None:
    result = await session.execute(select(Transaction).where(Transaction.id == transaction_id))
    txn = result.scalar_one_or_none()
    if txn is None:
        return None
    if txn.payer_id != user_id and txn.payee_id != user_id:
        return None
    return txn


def is_hold_active(txn: Transaction) -> bool:
    # `hold_expires_at` is declared `sa_type=DateTime(timezone=True)`
    # (app/models/transaction.py) and expected to always round-trip
    # tz-aware via Postgres/asyncpg -- but the structurally identical
    # comparison in listing_service.py's list_host_listings threw "can't
    # compare offset-naive and offset-aware datetimes" in production
    # against real Postgres, contradicting that assumption (see that
    # function's own comment for the incident). Normalized defensively
    # here too, since a raised TypeError from FEAT-032's booking hold check
    # is a P0 payment-flow failure, not just a dashboard display glitch.
    hold_expires_at = txn.hold_expires_at
    if hold_expires_at is not None and hold_expires_at.tzinfo is None:
        hold_expires_at = hold_expires_at.replace(tzinfo=UTC)
    return (
        txn.status in ("held", "pending_payment")
        and hold_expires_at is not None
        and hold_expires_at > datetime.now(UTC)
    )
