"""Search & Discovery endpoints -- FEAT-006 (Geospatial "Near Me" Search),
FEAT-007 (Listing Filters & Sort), FEAT-031 (Semantic Property Search,
degraded/keyword-only path). Backs Screen 5 (Search Results) in screens.md.

Public/unauthenticated: browsing listings does not require a session, per
user_flow.md's Flow 0 (a guest can search before signing up).
"""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, get_current_user_optional
from app.schemas.search import (
    CommercialSubtype,
    DealTypeFilter,
    ListingTypeFilter,
    SearchFilters,
    SearchResponse,
    ShortletSubtype,
    SortDirection,
    SortField,
)
from app.services import analytics_service
from app.services.search_service import DEFAULT_PAGE_SIZE, search_listings

router = APIRouter()


@router.get("/listings", response_model=SearchResponse)
async def search_listings_endpoint(
    session: Annotated[AsyncSession, Depends(get_session)],
    current_user: Annotated[CurrentUser | None, Depends(get_current_user_optional)] = None,
    latitude: float | None = Query(default=None, ge=-90, le=90),
    longitude: float | None = Query(default=None, ge=-180, le=180),
    radius_km: float = Query(default=10.0, gt=0, le=200),
    query: str | None = Query(default=None, max_length=200),
    listing_type: ListingTypeFilter | None = None,
    deal_type: DealTypeFilter | None = None,
    commercial_subtype: CommercialSubtype | None = None,
    shortlet_subtype: ShortletSubtype | None = None,
    min_price: float | None = Query(default=None, ge=0),
    max_price: float | None = Query(default=None, ge=0),
    min_size_sqm: float | None = Query(default=None, ge=0),
    max_size_sqm: float | None = Query(default=None, ge=0),
    bathrooms: int | None = Query(default=None, ge=0),
    amenities: list[str] | None = Query(default=None),
    legal_documents: list[str] | None = Query(default=None),
    verified_only: bool = False,
    sort_by: SortField = SortField.newest,
    sort_direction: SortDirection = SortDirection.desc,
    cursor: str | None = None,
    page_size: int = Query(default=DEFAULT_PAGE_SIZE, ge=1, le=50),
) -> SearchResponse:
    """GET /v1/search/listings -- Screen 5's `GET /listings/search`
    equivalent (mounted under the search router's `/search` prefix, per
    app/api/v1/__init__.py's existing router layout).

    Accepts either device coordinates (latitude/longitude, from GPS) or a
    pre-geocoded address/landmark (the client/a future geocoding endpoint
    resolves free text to lat/lng via Google Maps API -- not implemented
    here since GOOGLE_MAPS_API_KEY is REPLACE_ME; this endpoint only
    consumes coordinates).
    """
    try:
        filters = SearchFilters(
            latitude=latitude,
            longitude=longitude,
            radius_km=radius_km,
            query=query,
            listing_type=listing_type,
            deal_type=deal_type,
            commercial_subtype=commercial_subtype,
            shortlet_subtype=shortlet_subtype,
            min_price=min_price,
            max_price=max_price,
            min_size_sqm=min_size_sqm,
            max_size_sqm=max_size_sqm,
            bathrooms=bathrooms,
            amenities=amenities,
            legal_documents=legal_documents,
            verified_only=verified_only,
            sort_by=sort_by,
            sort_direction=sort_direction,
        )
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    try:
        page = await search_listings(session, filters, cursor, page_size)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    # FEAT-028: only the first page of a search counts as "a search was
    # performed" -- cursor-paginated continuations of the same query are
    # not a new funnel event.
    if cursor is None:
        await analytics_service.track_event(
            event_name=analytics_service.SEARCH_PERFORMED,
            user_id=current_user.user_id if current_user else None,
            properties={
                "listing_type": listing_type.value if listing_type else None,
                "deal_type": deal_type.value if deal_type else None,
                "has_query_text": query is not None,
                "has_location": latitude is not None and longitude is not None,
                "result_count": len(page.results),
            },
        )

    return SearchResponse(
        results=page.results,
        next_cursor=page.next_cursor,
        has_more=page.has_more,
    )
