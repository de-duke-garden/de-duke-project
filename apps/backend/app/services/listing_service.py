"""Business logic for listing creation/update, image handling, and
availability -- FEAT-004, FEAT-005, FEAT-008.


Note: bathrooms (Commercial + Shortlet) and shortlet subtype were
confirmed schema.md gaps during Phase B review, backfilled onto the
shared models and wired up here.
"""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from typing import Any

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.host_account import HostAccount
from app.models.listing import (
    CommercialListing,
    CommercialListingRoom,
    Listing,
    ListingImage,
    ShortletListing,
)
from app.models.transaction import Transaction
from app.schemas.listing import CommercialListingIn, ListingCreateIn, ShortletListingIn


def derive_status_for_new_listing(host_type: str) -> tuple[str, str | None]:
    """FEAT-008 auto-approval rule.

    Non-owner host types (agent, company, lawyer, architect, surveyor) have
    already been through document verification to reach `verified`
    HostAccount status, so their listings publish straight to `active`.
    Owner-type hosts have no document verification step, so their first (and
    every) listing goes to `under_review` for staff moderation.
    """
    if host_type == "owner":
        return "under_review", None
    return "active", None


def make_location_point_wkt(latitude: float, longitude: float) -> str:
    """WKT representation for the Geography(POINT, 4326) column. The server
    always derives this from server-validated lat/lng -- the client never
    supplies location_point directly."""
    return f"SRID=4326;POINT({longitude} {latitude})"


async def create_listing(
    session: AsyncSession,
    *,
    host_account: HostAccount,
    payload: ListingCreateIn,
) -> Listing:
    if payload.listing_type == "commercial" and payload.commercial is None:
        raise ValueError("commercial payload required for listing_type=commercial")
    if payload.listing_type == "shortlet" and payload.shortlet is None:
        raise ValueError("shortlet payload required for listing_type=shortlet")

    status_value, status_reason = derive_status_for_new_listing(host_account.host_type)

    listing = Listing(
        host_account_id=host_account.id,
        listing_type=payload.listing_type,
        title=payload.title,
        description=payload.description,
        location_latitude=payload.location.latitude,
        location_longitude=payload.location.longitude,
        location_address_line=payload.location.address_line,
        location_city=payload.location.city,
        location_state=payload.location.state,
        location_point=make_location_point_wkt(
            payload.location.latitude, payload.location.longitude
        ),
        amenities=payload.amenities,
        status=status_value,
        status_reason=status_reason,
    )
    session.add(listing)
    await session.flush()  # assign listing.id

    if payload.listing_type == "commercial" and payload.commercial is not None:
        await create_commercial_subtype(session, listing.id, payload.commercial)
    elif payload.listing_type == "shortlet" and payload.shortlet is not None:
        create_shortlet_subtype(session, listing.id, payload.shortlet)

    await session.commit()
    await session.refresh(listing)
    return listing


async def create_commercial_subtype(
    session: AsyncSession, listing_id: str, data: CommercialListingIn
) -> CommercialListing:
    possession_period_days = data.possession_period_days
    if data.deal_type == "lease" and possession_period_days is None:
        possession_period_days = 365  # default per schema.md comment
    if data.deal_type == "sale":
        possession_period_days = None

    commercial = CommercialListing(
        listing_id=listing_id,
        deal_type=data.deal_type,
        price=data.price,
        possession_period_days=possession_period_days,
        size_square_meters=data.size_square_meters,
        property_subtype=data.property_subtype,
        bathrooms=data.bathrooms,
        legal_documents=data.legal_documents,
    )
    session.add(commercial)
    await session.flush()

    for room in data.rooms:
        session.add(
            CommercialListingRoom(
                commercial_listing_id=commercial.id,
                level=room.level,
                width_meters=room.width_meters,
                length_meters=room.length_meters,
            )
        )
    return commercial


def create_shortlet_subtype(
    session: AsyncSession, listing_id: str, data: ShortletListingIn
) -> ShortletListing:
    shortlet = ShortletListing(
        listing_id=listing_id,
        nightly_price=data.nightly_price,
        minimum_stay_nights=data.minimum_stay_nights,
        maximum_stay_nights=data.maximum_stay_nights,
        bedrooms=data.bedrooms,
        bathrooms=data.bathrooms,
        subtype=data.subtype,
        house_rules=data.house_rules,
        blocked_dates=data.blocked_dates,
    )
    session.add(shortlet)
    return shortlet


def _daterange(start: date, end: date) -> list[date]:
    days = (end - start).days
    return [start.__class__.fromordinal(start.toordinal() + i) for i in range(days + 1)]


def dates_overlap(
    requested_start: date,
    requested_end: date,
    other_start: date,
    other_end: date,
) -> bool:
    """Inclusive-range overlap check shared by both booking-conflict sources
    (Transaction possession periods and ShortletListing.blocked_dates)."""
    return requested_start <= other_end and requested_end >= other_start


async def is_listing_available(
    session: AsyncSession,
    *,
    listing_id: str,
    start_date: date,
    end_date: date,
) -> tuple[bool, list[str]]:
    """Double-booking check for a listing over [start_date, end_date].

    Two sources of truth are consulted, per the pre-derived findings:
      1. `Transaction.possession_period_start_date/end_date` for any
         transaction on this listing that is held/succeeded (not
         failed/expired/refunded) and overlaps the requested range.
      2. `ShortletListing.blocked_dates` (host-managed calendar blocks),
         for shortlet listings only.

    Exposed here (not in bookings.py, which Subagent 5 owns) so Subagent 5
    can `from app.services.listing_service import is_listing_available`
    during merge without a circular import back into this module.

    Returns (is_available, conflicting_dates) where conflicting_dates is a
    list of ISO date strings that collide with the request, for surfacing
    on the availability calendar UI.
    """
    if start_date > end_date:
        raise ValueError("start_date must be <= end_date")

    conflicts: set[str] = set()

    non_blocking_statuses = ("failed", "expired", "refunded")
    stmt = select(Transaction).where(
        Transaction.listing_id == listing_id,
        Transaction.status.not_in(non_blocking_statuses),
        Transaction.possession_period_start_date.is_not(None),
        Transaction.possession_period_end_date.is_not(None),
    )
    result = await session.execute(stmt)
    for txn in result.scalars().all():
        txn_start = txn.possession_period_start_date.date()
        txn_end = txn.possession_period_end_date.date()
        if dates_overlap(start_date, end_date, txn_start, txn_end):
            for d in _daterange(max(start_date, txn_start), min(end_date, txn_end)):
                conflicts.add(d.isoformat())

    shortlet_stmt = select(ShortletListing).where(ShortletListing.listing_id == listing_id)
    shortlet_result = await session.execute(shortlet_stmt)
    shortlet = shortlet_result.scalar_one_or_none()
    if shortlet is not None:
        requested_iso = {d.isoformat() for d in _daterange(start_date, end_date)}
        conflicts |= requested_iso & set(shortlet.blocked_dates)

    return (len(conflicts) == 0, sorted(conflicts))


def listing_to_dict(
    listing: Listing,
    images: list[ListingImage],
    commercial: CommercialListing | None = None,
    commercial_rooms: list[CommercialListingRoom] | None = None,
    shortlet: ShortletListing | None = None,
    host_account: Any | None = None,
) -> dict[str, Any]:
    """Assembles the API response dict for a Listing + its subtype row +
    images, matching ListingOut.

    `host_account` (FEAT-042) is the owning HostAccount row, optional so
    every existing call site that doesn't have it handy yet doesn't break
    -- when provided, its bio/photo/type populate the Host Profile card on
    Listing Detail (mobile) and the Admin Web Console's Chat Oversight
    property context panel, closing the long-documented-but-never-built
    "shown on their listings" intent for HostAccount.bio (schema.md).
    """
    out: dict[str, Any] = {
        "id": listing.id,
        "host_account_id": listing.host_account_id,
        "listing_type": listing.listing_type,
        "title": listing.title,
        "description": listing.description,
        "location_latitude": listing.location_latitude,
        "location_longitude": listing.location_longitude,
        "location_address_line": listing.location_address_line,
        "location_city": listing.location_city,
        "location_state": listing.location_state,
        "amenities": listing.amenities,
        "status": listing.status,
        "status_reason": listing.status_reason,
        "view_count": listing.view_count,
        "inquiry_count": listing.inquiry_count,
        "owner_client_name": listing.owner_client_name,
        "host_bio": host_account.bio if host_account is not None else None,
        "host_photo_url": host_account.host_photo_url if host_account is not None else None,
        "host_type": host_account.host_type if host_account is not None else None,
        "images": [
            {
                "id": img.id,
                "image_url": img.image_url,
                "display_order": img.display_order,
                "is_primary": img.is_primary,
            }
            for img in sorted(images, key=lambda i: i.display_order)
        ],
        "commercial": None,
        "shortlet": None,
    }
    if commercial is not None:
        out["commercial"] = {
            "deal_type": commercial.deal_type,
            "price": commercial.price,
            "possession_period_days": commercial.possession_period_days,
            "size_square_meters": commercial.size_square_meters,
            "property_subtype": commercial.property_subtype,
            "legal_documents": commercial.legal_documents,
            "rooms": [
                {
                    "level": r.level,
                    "width_meters": r.width_meters,
                    "length_meters": r.length_meters,
                }
                for r in (commercial_rooms or [])
            ],
        }
    if shortlet is not None:
        out["shortlet"] = {
            "nightly_price": shortlet.nightly_price,
            "minimum_stay_nights": shortlet.minimum_stay_nights,
            "maximum_stay_nights": shortlet.maximum_stay_nights,
            "bedrooms": shortlet.bedrooms,
            "house_rules": shortlet.house_rules,
            "blocked_dates": shortlet.blocked_dates,
        }
    return out


def touch_updated_at(listing: Listing) -> None:
    listing.updated_at = datetime.now(UTC)


async def increment_view_count(session: AsyncSession, listing_id: str) -> None:
    """FEAT-017 (Host Dashboard) AC: listing cards show view counts.
    `Listing.view_count` existed in the model since Phase 1 but was never
    actually incremented anywhere -- confirmed gap, fixed here. Called from
    GET /v1/listings/{listing_id} (app/api/v1/listings.py), the one
    genuine "someone looked at this listing" read path -- deliberately NOT
    called from the create/update paths that also load a listing bundle,
    since those aren't views.

    Uses a direct UPDATE (not a SELECT-then-increment-in-Python round
    trip) so concurrent views never lose an increment to a race -- this
    endpoint is public/high-traffic and unauthenticated, so contention is
    expected, not an edge case.
    """
    await session.execute(
        update(Listing).where(Listing.id == listing_id).values(view_count=Listing.view_count + 1)
    )
    await session.commit()


# FEAT-017 AC: "Dashboard flags listings with zero activity after a set
# period." No existing config surface for this (unlike, say, commission
# rates' FEAT-027 admin-configurable table) -- a plain module constant,
# same tier of "business rule that could later move to config" as
# booking_hold_duration_minutes in app/core/config.py.
STALE_LISTING_THRESHOLD_DAYS = 14


async def list_host_listings(
    session: AsyncSession, *, host_account_id: str
) -> list[dict[str, Any]]:
    """GET /v1/host/listings (Screen 12, FEAT-017) -- every listing owned by
    the caller's own HostAccount, newest first, with the dashboard-specific
    `is_stale` flag computed here rather than left to the client.
    """
    result = await session.execute(
        select(Listing)
        .where(Listing.host_account_id == host_account_id)
        .order_by(Listing.created_at.desc())
    )
    listings = list(result.scalars().all())
    if not listings:
        return []

    listing_ids = [listing.id for listing in listings]
    images_result = await session.execute(
        select(ListingImage)
        .where(ListingImage.listing_id.in_(listing_ids))
        .where(ListingImage.is_primary == True)  # noqa: E712 -- SQLAlchemy column comparison, not a Python bool check
    )
    primary_image_by_listing = {
        img.listing_id: img.image_url for img in images_result.scalars().all()
    }

    now = datetime.now(UTC)
    stale_cutoff = now - timedelta(days=STALE_LISTING_THRESHOLD_DAYS)

    items = []
    for listing in listings:
        is_stale = (
            listing.view_count == 0
            and listing.inquiry_count == 0
            and listing.created_at < stale_cutoff
        )
        items.append(
            {
                "id": listing.id,
                "title": listing.title,
                "listing_type": listing.listing_type,
                "status": listing.status,
                "status_reason": listing.status_reason,
                "view_count": listing.view_count,
                "inquiry_count": listing.inquiry_count,
                "primary_image_url": primary_image_by_listing.get(listing.id),
                "is_stale": is_stale,
            }
        )
    return items
