"""Business logic for Saved Searches & Listing Alerts -- FEAT-023.

Two responsibilities live here:
1. CRUD for a seeker's own `SavedSearch` rows (backs Screen 20 + Screen 5's
   "Save this search" exit point).
2. The pure matching predicate (`listing_matches_saved_search`) used by
   `app/workers/saved_search_alert_job.py` to decide whether a newly
   published listing matches a given saved search.

Geospatial note: `SavedSearch.location_query` is a free-text string (per
the already-existing `app/models/discovery.py` model -- not recreated
here). `create_saved_search`/`update_saved_search` best-effort geocode it
via app/services/geocoding_service.py (Google Geocoding API,
GOOGLE_MAPS_API_KEY) into `location_latitude`/`location_longitude` --
best-effort because geocoding can fail (outage, unresolvable address,
unconfigured key) and must never block saving a search (AGENTS.md's
"degrade gracefully rather than cascading failure" rule). When
coordinates ARE available (on both the search and the candidate listing),
`listing_matches_saved_search` runs a real haversine-distance `radius_km`
check; otherwise it falls back to a case-insensitive substring match of
`location_query` against the listing's city/state/address line.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.discovery import SavedSearch
from app.schemas.saved_search import SavedSearchCreate, SavedSearchUpdate
from app.services.geocoding_service import geocode_address

_EARTH_RADIUS_KM = 6371.0


async def create_saved_search(
    session: AsyncSession, *, user_id: str, payload: SavedSearchCreate
) -> SavedSearch:
    coordinates = await geocode_address(payload.location_query)
    saved_search = SavedSearch(
        user_id=user_id,
        label=payload.label,
        location_query=payload.location_query,
        radius_km=payload.radius_km,
        listing_type=payload.listing_type,
        min_price=payload.min_price,
        max_price=payload.max_price,
        verified_only=payload.verified_only,
        alerts_enabled=payload.alerts_enabled,
        location_latitude=coordinates[0] if coordinates else None,
        location_longitude=coordinates[1] if coordinates else None,
    )
    session.add(saved_search)
    await session.commit()
    await session.refresh(saved_search)
    return saved_search


async def list_saved_searches(session: AsyncSession, *, user_id: str) -> list[SavedSearch]:
    """Most recently created first -- Screen 20 is an unpaginated `ListView`."""
    result = await session.execute(
        select(SavedSearch)
        .where(SavedSearch.user_id == user_id)
        .order_by(SavedSearch.created_at.desc())
    )
    return list(result.scalars().all())


async def get_owned_saved_search(
    session: AsyncSession, *, user_id: str, saved_search_id: str
) -> SavedSearch:
    """Fetches a saved search, enforcing ownership server-side (AGENTS.md:
    "Enforce role/permission checks server-side") -- a seeker may only
    view/edit/delete their own saved searches, never another user's by ID
    guessing. Raises 404 (not 403) for both "doesn't exist" and "exists but
    isn't yours" so the response doesn't leak which IDs are valid."""
    result = await session.execute(
        select(SavedSearch)
        .where(SavedSearch.id == saved_search_id)
        .where(SavedSearch.user_id == user_id)
    )
    saved_search = result.scalar_one_or_none()
    if saved_search is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Saved search not found.")
    return saved_search


async def update_saved_search(
    session: AsyncSession, *, user_id: str, saved_search_id: str, payload: SavedSearchUpdate
) -> SavedSearch:
    saved_search = await get_owned_saved_search(
        session, user_id=user_id, saved_search_id=saved_search_id
    )

    if payload.label is not None:
        saved_search.label = payload.label
    if payload.location_query is not None and payload.location_query != saved_search.location_query:
        saved_search.location_query = payload.location_query
        coordinates = await geocode_address(payload.location_query)
        saved_search.location_latitude = coordinates[0] if coordinates else None
        saved_search.location_longitude = coordinates[1] if coordinates else None
    if payload.radius_km is not None:
        saved_search.radius_km = payload.radius_km
    if payload.clear_listing_type:
        saved_search.listing_type = None
    elif payload.listing_type is not None:
        saved_search.listing_type = payload.listing_type
    if payload.min_price is not None:
        saved_search.min_price = payload.min_price
    if payload.max_price is not None:
        saved_search.max_price = payload.max_price
    if payload.verified_only is not None:
        saved_search.verified_only = payload.verified_only
    if payload.alerts_enabled is not None:
        saved_search.alerts_enabled = payload.alerts_enabled

    session.add(saved_search)
    await session.commit()
    await session.refresh(saved_search)
    return saved_search


async def delete_saved_search(session: AsyncSession, *, user_id: str, saved_search_id: str) -> None:
    saved_search = await get_owned_saved_search(
        session, user_id=user_id, saved_search_id=saved_search_id
    )
    await session.delete(saved_search)
    await session.commit()


@dataclass(frozen=True)
class ListingSnapshot:
    """The subset of a published listing's fields the matching predicate
    needs, decoupled from the ORM `Listing`/`CommercialListing`/
    `ShortletListing` tables so `listing_matches_saved_search` can be unit
    tested without a live Postgres/PostGIS instance (mirrors
    `app/services/booking_service.is_hold_active`'s pure-function pattern,
    per `test_hold_expiry_pure.py`'s precedent in this codebase)."""

    listing_type: str
    price: float | None
    is_verified_host: bool
    location_city: str
    location_state: str
    location_address_line: str
    location_latitude: float | None = None
    location_longitude: float | None = None


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in km -- a pure-Python equivalent of the
    PostGIS `ST_Distance`/`ST_DWithin` geography calculation used
    elsewhere (app/services/search_service.py), needed here because this
    predicate is intentionally DB-free (see ListingSnapshot's docstring
    precedent) and runs against plain floats already loaded onto
    SavedSearch/ListingSnapshot rather than a live spatial query."""
    r1, r2 = math.radians(lat1), math.radians(lat2)
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat / 2) ** 2 + math.cos(r1) * math.cos(r2) * math.sin(dlon / 2) ** 2
    return 2 * _EARTH_RADIUS_KM * math.asin(math.sqrt(a))


def listing_matches_saved_search(search: SavedSearch, listing: ListingSnapshot) -> bool:
    """Pure predicate: does `listing` satisfy every filter on `search`?

    Every filter is optional/None-means-"don't filter on this", matching
    `app/services/search_service.py`'s own filter-building convention.
    """
    if search.listing_type is not None and listing.listing_type != search.listing_type:
        return False

    if search.verified_only and not listing.is_verified_host:
        return False

    if search.min_price is not None and (listing.price is None or listing.price < search.min_price):
        return False

    if search.max_price is not None and (listing.price is None or listing.price > search.max_price):
        return False

    location_query = search.location_query.strip().lower()
    if location_query:
        has_coordinates = (
            search.location_latitude is not None
            and search.location_longitude is not None
            and listing.location_latitude is not None
            and listing.location_longitude is not None
        )
        if has_coordinates:
            distance_km = _haversine_km(
                search.location_latitude,
                search.location_longitude,
                listing.location_latitude,
                listing.location_longitude,
            )
            if distance_km > search.radius_km:
                return False
        else:
            # Degraded path -- one or both sides were never successfully
            # geocoded (unconfigured/failed Google Geocoding call).
            haystack = " ".join(
                [listing.location_city, listing.location_state, listing.location_address_line]
            ).lower()
            if location_query not in haystack:
                return False

    return True
