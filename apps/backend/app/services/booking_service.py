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

from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models.host_account import HostAccount
from app.models.listing import CommercialListing, Listing, ShortletListing
from app.models.transaction import Transaction
from app.services.commission_service import compute_price_breakdown, get_effective_rates

settings = get_settings()

# Transaction statuses that still hold/consume a listing's availability.
# 'payment_received'/'released_to_wallet' are the two escrow-model
# statuses (schema.md) that both mean "the guest paid" -- they must both
# keep blocking the listing/dates regardless of whether a De-Duke Admin
# has released the funds to the payee's Wallet yet (FEAT-043), since
# release is purely about WHEN the payee is credited, not whether the
# booking itself is confirmed.
NON_TERMINAL_STATUSES = ("held", "pending_payment", "payment_received", "released_to_wallet")


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
    until we commit/rollback.

    Bug fix: previously blocked on `status.in_(NON_TERMINAL_STATUSES)` alone
    -- `held`/`pending_payment` rows count as blocking purely by status,
    with no check of whether `hold_expires_at` has already passed. That
    status transition to `expired` is only ever performed by
    `hold_expiry_job.expire_stale_holds`, a "pure transition function"
    this codebase never actually wires up to run on a schedule anywhere
    (no cron entrypoint, no infra trigger) -- so in practice a hold's row
    just stays `held` forever once it expires, and every retry after the
    countdown hits zero was told the dates are still unavailable,
    indefinitely. Fixed here by also treating a `held`/`pending_payment`
    row whose `hold_expires_at` has already passed as non-blocking,
    regardless of whether the batch job has gotten to it yet -- the
    correctness of this check no longer depends on that job running at
    all. A transaction that has been paid (`payment_received` or, later,
    `released_to_wallet` -- schema.md's escrow model) is exempt from this
    (a paid booking has no expiry and must always keep blocking,
    regardless of whether a De-Duke Admin has released its funds yet).
    """
    now = datetime.now(UTC)
    still_active_hold = and_(
        Transaction.status.in_(("held", "pending_payment")),
        or_(
            Transaction.hold_expires_at.is_(None),
            Transaction.hold_expires_at >= now,
        ),
    )
    result = await session.execute(
        select(Transaction.id)
        .where(Transaction.listing_id == listing_id)
        .where(
            or_(
                Transaction.status.in_(("payment_received", "released_to_wallet")),
                still_active_hold,
            )
        )
        .where(Transaction.possession_period_start_date < end)
        .where(Transaction.possession_period_end_date > start)
        .with_for_update()
    )
    return result.first() is not None


async def _expire_stale_holds_for_listing(session: AsyncSession, listing_id: str) -> None:
    """Self-healing companion to the fix above -- opportunistically
    transitions this listing's own past-expiry `held`/`pending_payment`
    rows to `expired` right here, while `create_hold` already holds the
    listing row lock (see `_lock_listing_row`), rather than leaving that
    entirely to the never-actually-scheduled `hold_expiry_job`. This
    keeps the data itself correct (host dashboards, transaction history,
    disputes all read `status` directly and would otherwise show a stale
    `held` row forever) rather than only correct from
    `_has_overlapping_hold`'s point of view. Scoped to one listing (not a
    global sweep) since that's the only lock this call site already
    holds; the batch job -- once actually wired to run on a schedule,
    still a real infra gap -- remains responsible for the rest of the
    table.
    """
    now = datetime.now(UTC)
    result = await session.execute(
        select(Transaction)
        .where(Transaction.listing_id == listing_id)
        .where(Transaction.status.in_(("held", "pending_payment")))
        .where(Transaction.hold_expires_at.is_not(None))
        .where(Transaction.hold_expires_at < now)
    )
    for txn in result.scalars().all():
        txn.status = "expired"
        session.add(txn)


async def _compute_possession_period(
    session: AsyncSession,
    listing: Listing,
    check_in_date: datetime | None,
    check_out_date: datetime | None,
) -> tuple[datetime, datetime, float]:
    """Returns (start, end, listing_price) -- `listing_price` is the raw
    listing/deal price BEFORE either commission component (see
    Transaction.listing_price's own docstring); confirm_booking below
    applies the two-sided commission math on top of this value."""
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
        listing_price = nights * shortlet.nightly_price
        return check_in_date, check_out_date, listing_price

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

    start, end, listing_price = await _compute_possession_period(
        session, listing, check_in_date, check_out_date
    )

    # Self-heal this listing's own stale holds while we already hold its
    # row lock -- see that function's docstring for why this can't be left
    # entirely to the (never actually scheduled) hold_expiry_job.
    await _expire_stale_holds_for_listing(session, listing_id)

    # Re-check overlap now that the listing row (and any competing
    # transactions) are locked -- closes the check-then-write race window.
    if await _has_overlapping_hold(session, listing_id, start, end):
        raise ListingUnavailableError("These dates are no longer available")

    # Bug fix: Transaction.payee_id has a foreign key to users.id (see
    # app/models/transaction.py), but `listing.host_account_id` is a
    # host_accounts.id -- a different table/primary key entirely (see
    # app/models/host_account.py's HostAccount.id vs. HostAccount.user_id).
    # For any individually-owned (non-agency) listing this inserted a
    # HostAccount id into a column that only ever validates against real
    # User rows, throwing ForeignKeyViolationError on every confirm_booking
    # call for that listing -- 100% reproducible, not a race/edge case.
    # `listing.agency_id` is unaffected (agency_service.py already
    # resolves it to the agency root's *users.id* at listing-creation
    # time), so only the individual-host fallback needed fetching the
    # HostAccount row to resolve its owning user.
    if listing.agency_id is not None:
        payee_id = listing.agency_id
    else:
        host_account = await session.get(HostAccount, listing.host_account_id)
        if host_account is None:
            raise ListingUnavailableError("Listing's host account no longer exists")
        payee_id = host_account.user_id

    transaction_type = transaction_type_for_listing(listing, commercial)

    # Two-sided commission model (product decision): both rates are
    # snapshotted HERE, at hold creation, not deferred to payment-webhook
    # time -- gross_amount (the actual Paystack charge amount) must
    # already include the buyer fee before checkout can even initiate the
    # transaction, so this can no longer be computed lazily the way the
    # old single-rate model was. `as_of=now` matches the old model's own
    # snapshot instant (it resolved the rate `as_of=txn.created_at`, just
    # lazily at webhook time) -- same rate-resolution semantics, computed
    # once instead of twice.
    buyer_fee_pct, owner_commission_pct = await get_effective_rates(
        session, transaction_type, as_of=datetime.now(UTC)
    )
    breakdown = compute_price_breakdown(listing_price, buyer_fee_pct, owner_commission_pct)

    txn = Transaction(
        listing_id=listing_id,
        payer_id=payer_id,
        payee_id=payee_id,
        transaction_type=transaction_type,
        listing_price=breakdown.listing_price,
        buyer_fee_amount=breakdown.buyer_fee_amount,
        owner_commission_amount=breakdown.owner_commission_amount,
        gross_amount=breakdown.gross_amount,
        net_payout_amount=breakdown.net_payout_amount,
        commission_amount=breakdown.commission_amount,
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
