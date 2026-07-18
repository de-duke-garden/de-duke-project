"""Business logic for listing creation/update, image handling, and
availability -- FEAT-004, FEAT-005, FEAT-008.


Note: bathrooms (Commercial + Shortlet) and shortlet subtype were
confirmed schema.md gaps during Phase B review, backfilled onto the
shared models and wired up here.
"""

from __future__ import annotations

import logging
import subprocess
import tempfile
from datetime import UTC, date, datetime, timedelta
from pathlib import Path
from typing import Any

import anyio
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.host_account import HostAccount
from app.models.listing import (
    CommercialListing,
    CommercialListingRoom,
    Listing,
    ListingMedia,
    ShortletListing,
)
from app.models.transaction import Transaction
from app.schemas.listing import CommercialListingIn, ListingCreateIn, ShortletListingIn

logger = logging.getLogger("app.services.listing_service")

# FEAT-004/FEAT-005 acceptance criteria (docs/De-Duke/features.md, product-
# shaped via product-shaper) -- a video clip is capped at 100MB / 5 minutes,
# and a listing can carry at most 5 video clips (on top of however many
# photos). Validated server-side, never trusted from the client alone.
MAX_VIDEO_BYTES = 100 * 1024 * 1024
MAX_VIDEO_DURATION_SECONDS = 5 * 60
MAX_VIDEOS_PER_LISTING = 5

# Bounded timeout for the ffmpeg/ffprobe subprocess calls below -- same
# "never let a hung external dependency pile up slow requests" reasoning
# as every other external call in this codebase (AGENTS.md Behavior
# Rules), even though ffmpeg is a local binary, not a network dependency:
# a malformed/adversarial video file can still make it hang.
_FFMPEG_TIMEOUT_SECONDS = 30


class VideoValidationError(ValueError):
    """A video upload violates FEAT-004/FEAT-005's documented limits (file
    size, clip length, or per-listing count) -- mapped to a 422 by the
    router. Distinct from a processing failure (see ListingMedia.
    processing_status's docstring): this is a hard rejection the caller
    must fix before retrying, not a degraded-but-accepted upload."""


def _probe_and_extract_poster_sync(video_bytes: bytes) -> tuple[float, bytes]:
    """The actual blocking ffmpeg/ffprobe work -- run off the event loop
    via anyio.to_thread by `process_uploaded_video` below, mirroring
    push_service._send_multicast_sync's own "real external-tool call, run
    in a worker thread" pattern.

    Writes `video_bytes` to a temp file (ffmpeg/ffprobe both require a
    real file path, not a stream) and returns (duration_seconds,
    poster_jpeg_bytes). Raises RuntimeError -- caught by the caller and
    treated as "processing failed" (ListingMedia.processing_status
    ='failed'), never propagated as a hard upload rejection, since a video
    that merely failed poster generation (e.g. an unusual codec ffmpeg
    can't read a frame from) should still be stored and playable, just
    without a poster -- see risk_log.md's R-021 for the tradeoff this
    reflects (reject non-conforming codecs at the client's declared
    content-type/extension level, degrade gracefully for anything that
    slips through server-side).
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        video_path = Path(tmpdir) / "input"
        video_path.write_bytes(video_bytes)
        poster_path = Path(tmpdir) / "poster.jpg"

        try:
            probe = subprocess.run(
                [
                    "ffprobe",
                    "-v", "error",
                    "-show_entries", "format=duration",
                    "-of", "default=noprint_wrappers=1:nokey=1",
                    str(video_path),
                ],
                capture_output=True,
                text=True,
                timeout=_FFMPEG_TIMEOUT_SECONDS,
                check=True,
            )
            duration_seconds = float(probe.stdout.strip())

            # 1s into the clip (falls back to the first frame ffmpeg can
            # decode if the clip is shorter than that) -- avoids a
            # frequently-black true-first-frame on phone camera footage.
            subprocess.run(
                [
                    "ffmpeg",
                    "-y",
                    "-ss", "00:00:01",
                    "-i", str(video_path),
                    "-frames:v", "1",
                    "-q:v", "3",
                    str(poster_path),
                ],
                capture_output=True,
                timeout=_FFMPEG_TIMEOUT_SECONDS,
                check=True,
            )
            poster_bytes = poster_path.read_bytes()
        except (
            OSError,
            ValueError,
            subprocess.CalledProcessError,
            subprocess.TimeoutExpired,
        ) as exc:
            raise RuntimeError(f"video processing failed: {exc}") from exc

    return duration_seconds, poster_bytes


async def process_uploaded_video(video_bytes: bytes) -> tuple[float | None, bytes | None]:
    """Probes clip duration and extracts a poster frame for a freshly
    uploaded video. Returns (None, None) if ffmpeg/ffprobe aren't
    available or the file couldn't be processed -- callers persist the
    video anyway with `processing_status='failed'` (graceful degradation,
    same "bounded timeout, fail fast, log and continue" pattern
    push_service.py/sms_service.py already establish) rather than
    rejecting an otherwise-valid upload over a poster-generation hiccup.
    """
    try:
        return await anyio.to_thread.run_sync(_probe_and_extract_poster_sync, video_bytes)
    except Exception as exc:  # noqa: BLE001 -- ffmpeg/subprocess raise many distinct types
        logger.warning("process_uploaded_video: failed (%s)", exc)
        return None, None


async def count_listing_videos(session: AsyncSession, listing_id: str) -> int:
    """Backs the MAX_VIDEOS_PER_LISTING check -- counts already-persisted
    video rows so a second upload request against the same listing (e.g.
    Edit Listing adding more clips later) is checked against the true
    total, not just what's in the current request batch."""
    result = await session.execute(
        select(func.count())
        .select_from(ListingMedia)
        .where(ListingMedia.listing_id == listing_id, ListingMedia.media_type == "video")
    )
    return result.scalar_one()


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
    agency_id: str | None = None,
) -> Listing:
    if payload.listing_type == "commercial" and payload.commercial is None:
        raise ValueError("commercial payload required for listing_type=commercial")
    if payload.listing_type == "shortlet" and payload.shortlet is None:
        raise ValueError("shortlet payload required for listing_type=shortlet")

    status_value, status_reason = derive_status_for_new_listing(host_account.host_type)

    listing = Listing(
        host_account_id=host_account.id,
        # Resolved by the caller via agency_service.resolve_agency_id_for_listing
        # -- None for an individual host, the agency root's users.id for an
        # agency account (root or invited team member). Without this,
        # agency_service's Portfolio/Summary queries (which filter on
        # `Listing.agency_id == agency_id`) never match a listing this
        # account creates.
        agency_id=agency_id,
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
    media: list[ListingMedia],
    commercial: CommercialListing | None = None,
    commercial_rooms: list[CommercialListingRoom] | None = None,
    shortlet: ShortletListing | None = None,
    host_account: Any | None = None,
) -> dict[str, Any]:
    """Assembles the API response dict for a Listing + its subtype row +
    media (photos/videos), matching ListingOut.

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
        "media": [
            {
                "id": item.id,
                "media_type": item.media_type,
                "media_url": item.media_url,
                "poster_url": item.poster_url,
                "duration_seconds": item.duration_seconds,
                "processing_status": item.processing_status,
                "display_order": item.display_order,
                "is_primary": item.is_primary,
            }
            for item in sorted(media, key=lambda i: i.display_order)
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


def is_listing_stale(listing: Listing, *, now: datetime) -> bool:
    """FEAT-017 AC: "Dashboard flags listings with zero activity after a set
    period." Pure/no I/O -- split out from list_host_listings below so it's
    unit-testable without a live DB session, same as booking_service.py's
    is_hold_active.

    `listing.created_at` is declared `sa_type=DateTime(timezone=True)`
    (app/models/listing.py) and Postgres/asyncpg is expected to always
    round-trip that tz-aware -- but a bare `<` between it and a tz-aware
    cutoff threw "can't compare offset-naive and offset-aware datetimes" in
    production (development environment, real RDS Postgres, not the SQLite
    test harness this exact class of issue was previously attributed to --
    see ops_analytics_service.py's `_as_aware` and share_service.py's
    identical guard), for every newly-created listing (0 views, 0
    inquiries) reaching this check. Normalized defensively here rather than
    trusting the driver, matching this codebase's own established pattern
    for this exact class of bug.
    """
    if listing.view_count != 0 or listing.inquiry_count != 0:
        return False
    created_at = (
        listing.created_at
        if listing.created_at.tzinfo is not None
        else listing.created_at.replace(tzinfo=UTC)
    )
    stale_cutoff = now - timedelta(days=STALE_LISTING_THRESHOLD_DAYS)
    return created_at < stale_cutoff


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
    media_result = await session.execute(
        select(ListingMedia)
        .where(ListingMedia.listing_id.in_(listing_ids))
        .where(ListingMedia.is_primary == True)  # noqa: E712 -- SQLAlchemy column comparison, not a Python bool check
    )
    primary_image_by_listing = {
        item.listing_id: item.media_url for item in media_result.scalars().all()
    }

    now = datetime.now(UTC)

    items = []
    for listing in listings:
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
                "is_stale": is_listing_stale(listing, now=now),
            }
        )
    return items
