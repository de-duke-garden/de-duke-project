"""FEAT-023 -- Saved Search Alerts background job.

Periodically (intended cadence: every 15-20 minutes, well under FEAT-023's
"notified within about an hour" AC even accounting for queue/worker
scheduling jitter) sweeps every currently `active` listing against every
`alerts_enabled` saved search and pushes a notification for each new match,
following the same "pure transition function invoked periodically by the
Background Task Processor; wiring the actual SQS-triggered schedule is an
infra/worker-harness concern outside this slice" shape as
`app/workers/hold_expiry_job.py`.

Event-driven alternative considered and rejected: there is no existing
publish-event hook to attach to. A listing becomes `active` from two
different call sites -- `app/services/listing_service.py` (auto-approval
for already-verified host types, at creation) and
`app/services/moderation_service.py::apply_moderation_decision` (staff
approval of a previously `under_review` listing) -- neither of which
touches an event bus/SQS today, and both are owned by other feature slices
(Listings, Moderation), out of this slice's file boundaries. A periodic
full sweep, deduplicated via `SavedSearchAlertLog`'s unique
(saved_search_id, listing_id) constraint, is therefore the correct fit
here: it needs no changes to those other services, and dedup is exact
regardless of how many times the sweep runs or overlaps.
"""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

# app/models/discovery.py::SavedSearch -- imported at call time in
# `_load_alerts_enabled_searches` to keep this module's import surface
# minimal and avoid any accidental import-order coupling with the
# Search & Discovery slice's own models module.
from app.models.discovery import SavedSearch
from app.models.host_account import HostAccount
from app.models.listing import CommercialListing, Listing, ShortletListing
from app.models.saved_search_alert import SavedSearchAlertLog
from app.services import push_service
from app.services.saved_search_service import ListingSnapshot, listing_matches_saved_search


async def _load_alerts_enabled_searches(session: AsyncSession) -> list[SavedSearch]:
    result = await session.execute(select(SavedSearch).where(SavedSearch.alerts_enabled.is_(True)))
    return list(result.scalars().all())


async def _load_active_listings(session: AsyncSession) -> list[Listing]:
    result = await session.execute(select(Listing).where(Listing.status == "active"))
    return list(result.scalars().all())


async def _build_snapshot(session: AsyncSession, listing: Listing) -> ListingSnapshot:
    """Resolves the price (from whichever of CommercialListing/
    ShortletListing the polymorphic `Listing` row belongs to -- table-per-
    type, per AGENTS.md) and host verification status needed to evaluate
    `listing_matches_saved_search`."""
    price: float | None = None
    if listing.listing_type == "commercial":
        result = await session.execute(
            select(CommercialListing.price).where(CommercialListing.listing_id == listing.id)
        )
        price = result.scalar_one_or_none()
    elif listing.listing_type == "shortlet":
        result = await session.execute(
            select(ShortletListing.nightly_price).where(ShortletListing.listing_id == listing.id)
        )
        price = result.scalar_one_or_none()

    host_account = await session.get(HostAccount, listing.host_account_id)
    is_verified_host = bool(host_account and host_account.status == "verified")

    return ListingSnapshot(
        listing_type=listing.listing_type,
        price=price,
        is_verified_host=is_verified_host,
        location_city=listing.location_city,
        location_state=listing.location_state,
        location_address_line=listing.location_address_line,
        location_latitude=listing.location_latitude,
        location_longitude=listing.location_longitude,
    )


async def _already_notified(
    session: AsyncSession, *, saved_search_id: str, listing_id: str
) -> bool:
    result = await session.execute(
        select(SavedSearchAlertLog.id)
        .where(SavedSearchAlertLog.saved_search_id == saved_search_id)
        .where(SavedSearchAlertLog.listing_id == listing_id)
    )
    return result.scalar_one_or_none() is not None


async def _record_and_notify(
    session: AsyncSession, *, saved_search: SavedSearch, listing: Listing
) -> bool:
    """Inserts the dedupe row *before* sending -- if two overlapping sweeps
    race on the same (saved_search_id, listing_id) pair, the unique
    constraint on `SavedSearchAlertLog` makes the loser's insert fail
    (IntegrityError), and the loser skips sending rather than double-
    notifying. Returns True if a notification was sent."""
    session.add(SavedSearchAlertLog(saved_search_id=saved_search.id, listing_id=listing.id))
    try:
        await session.commit()
    except IntegrityError:
        await session.rollback()
        return False

    # Best-effort notification; a send failure must never roll back the
    # already-committed dedupe row -- FEAT-023's AC is "notified within a
    # reasonable time", not "notified exactly once guaranteed", so a
    # single missed push (e.g. FCM outage) is an acceptable degradation,
    # same tradeoff app/workers/hold_expiry_job.py makes for its own
    # notify_user calls.
    try:
        await push_service.notify_user(
            session,
            user_id=saved_search.user_id,
            template=push_service.SAVED_SEARCH_MATCH,
            context={"saved_search_id": saved_search.id, "listing_id": listing.id},
        )
    except Exception:  # noqa: BLE001 -- best-effort notification only
        pass

    return True


async def run_alert_sweep(session: AsyncSession) -> int:
    """Evaluates every `alerts_enabled` saved search against every
    currently `active` listing and sends a push per new match. Returns the
    count of notifications actually sent (i.e. excluding already-notified
    pairs) so a caller can emit a metric, mirroring
    `hold_expiry_job.expire_stale_holds`'s own return-count convention.
    """
    searches = await _load_alerts_enabled_searches(session)
    if not searches:
        return 0

    listings = await _load_active_listings(session)
    if not listings:
        return 0

    sent = 0
    for listing in listings:
        snapshot: ListingSnapshot | None = None
        for search in searches:
            if await _already_notified(session, saved_search_id=search.id, listing_id=listing.id):
                continue
            if snapshot is None:
                snapshot = await _build_snapshot(session, listing)
            if not listing_matches_saved_search(search, snapshot):
                continue
            if await _record_and_notify(session, saved_search=search, listing=listing):
                sent += 1

    return sent
