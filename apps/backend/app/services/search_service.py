"""Search & Discovery business logic -- FEAT-006 (Geospatial "Near Me"
Search), FEAT-007 (Listing Filters & Sort), FEAT-031 (Semantic Property
Search, degraded/keyword-only path).

Read-replica routing: architecture.md's Search & Discovery Component notes
that read-heavy search traffic should be routed to a read replica rather than
the Primary Database writer. This module takes an `AsyncSession` as a plain
dependency (see app/api/v1/search.py) rather than opening its own connection,
so replica routing is a connection-string/session-factory concern for
app/core/db.py to pick up later (e.g. a second engine bound to a replica
endpoint) -- not something this service should hardcode. Flagged as a
follow-up for whoever owns app/core/db.py, since Subagent 3 cannot edit that
shared file.

Caching: architecture.md calls for caching hot search results in Redis.
Not wired here because app/core has no shared Redis client dependency yet
(only `redis_url` in config.py) -- adding a cache-aside layer around
`search_listings()` is a straightforward follow-up once a shared
`get_redis()` dependency exists; the query-building logic below is written to
be cache-key-friendly (deterministic filter dict -> stable cache key).

KNOWN SCHEMA GAPS (do not fix here -- app/models is shared/read-only):
1. `bathrooms` -- FEAT-007 requires filtering by bathroom count for both
   Commercial and Shortlet listings. Neither `CommercialListing` nor
   `ShortletListing` (app/models/listing.py) has a `bathrooms` column today.
   The filter below is written against `getattr(CommercialListing,
   "bathrooms", None)` / `getattr(ShortletListing, "bathrooms", None)` so it
   is inert (raises no error, filters nothing) until the column exists, at
   which point deleting the `hasattr` guard is the only change needed.
   ACTION NEEDED: add `bathrooms: int` to both subtype tables, each with a
   btree index (`Field(index=True)`), via an expand-contract Alembic
   migration.
2. Embedding column for FEAT-031 -- schema.md's prose references vector
   embeddings for semantic search, but no embedding column/table is defined
   in schema.md's JSON Schema for Listing, and none exists in
   app/models/listing.py (see that file's own docstring making the same
   observation). Per FEAT-031's own acceptance criteria ("degrades gracefully
   to keyword/filter-only search... within a strict timeout"), this module
   implements ONLY the keyword/filter-only fallback path -- there is no
   ranking service to time out against yet, so `semantic_ranking_applied` is
   always False. ACTION NEEDED: add a `pgvector` `Vector` column (e.g.
   `Listing.description_embedding`) plus an HNSW/IVFFlat index, and a
   background worker (SQS-consumed, per architecture.md) that (re)embeds a
   listing within a few minutes of publish/edit, before real semantic ranking
   can be implemented.
3. Shortlet subtype (Hostel/Hotel/1/2/3 Bedroom) -- FEAT-007 requires
   filtering shortlet listings by this subtype, but `ShortletListing` only
   has `bedrooms: int`, with no field distinguishing "Hostel"/"Hotel" from an
   ordinary N-bedroom unit. The `shortlet_subtype` filter parameter
   (app/schemas/search.py) currently only maps onto `bedrooms` for the
   `*_bedroom` enum values and is a no-op for `hostel`/`hotel` until a
   `shortlet_subtype: str` column (indexed) is added to `ShortletListing`.

INDEX AUDIT (AGENTS.md: "every filterable/sortable field... backed by a
database index"), against the current (read-only) models:
- Listing.listing_type -- indexed (existing).
- Listing.status -- indexed (existing); always filtered to "active" here.
- Listing.location_city / location_state -- indexed (existing).
- Listing.location_point -- Geography column; NEEDS an explicit GiST index
  (`CREATE INDEX ... USING GIST (location_point)`) for ST_DWithin/<->
  performance at scale. Not present in the model file or a migration today.
  ACTION NEEDED.
- Listing.created_at -- used for "newest" sort and as a keyset pagination
  tiebreaker; NOT indexed today. ACTION NEEDED (btree index).
- CommercialListing.property_subtype -- indexed (existing).
- CommercialListing.deal_type -- NOT indexed today. ACTION NEEDED.
- CommercialListing.price / ShortletListing.nightly_price -- used for
  price filtering and "price" sort; NOT indexed today. ACTION NEEDED (btree
  on each).
- CommercialListing.size_square_meters -- used for size range filter; NOT
  indexed today. ACTION NEEDED.
- bathrooms -- see gap #1 above; index requested alongside the column.
- HostAccount.status ("verified") -- indexed (existing) via host_type/status
  columns, used for the "Verified Host" filter (joined through
  Listing.host_account_id, itself indexed).
- amenities / legal_documents (JSON array columns) -- containment filtering
  (`amenities @> ['parking']`) on a JSON column is not index-friendly at
  Postgres scale; ACTION NEEDED: consider a GIN index if these columns are
  migrated to `ARRAY(String)` or `JSONB` (currently generic `JSON`, which
  GIN cannot index as efficiently as `JSONB`). Flagging rather than silently
  reinterpreting the column type here.
"""

from __future__ import annotations

import base64
import json
from dataclasses import dataclass
from datetime import datetime

from geoalchemy2 import Geography
from sqlalchemy import Select, and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.models.host_account import HostAccount
from app.models.listing import CommercialListing, Listing, ShortletListing
from app.schemas.search import (
    ListingSearchResult,
    ListingTypeFilter,
    SearchFilters,
    SemanticSearchDegradedInfo,
    SortField,
)

DEFAULT_PAGE_SIZE = 20
MAX_PAGE_SIZE = 50


def _encode_cursor(sort_value: str, listing_id: str) -> str:
    payload = json.dumps({"v": sort_value, "id": listing_id})
    return base64.urlsafe_b64encode(payload.encode()).decode()


def _decode_cursor(cursor: str) -> tuple[str, str]:
    try:
        payload = json.loads(base64.urlsafe_b64decode(cursor.encode()).decode())
        return payload["v"], payload["id"]
    except Exception as exc:  # noqa: BLE001 -- surfaced as a 400 by the router
        raise ValueError("Invalid pagination cursor") from exc


@dataclass
class SearchPage:
    results: list[ListingSearchResult]
    next_cursor: str | None
    has_more: bool
    degraded_info: SemanticSearchDegradedInfo


def _build_base_query(filters: SearchFilters) -> tuple[Select, CommercialListing, ShortletListing]:
    commercial = aliased(CommercialListing)
    shortlet = aliased(ShortletListing)

    query = (
        select(Listing, commercial, shortlet, HostAccount)
        .outerjoin(commercial, commercial.listing_id == Listing.id)
        .outerjoin(shortlet, shortlet.listing_id == Listing.id)
        .outerjoin(HostAccount, HostAccount.id == Listing.host_account_id)
        .where(Listing.status == "active")
    )

    if filters.listing_type is not None:
        query = query.where(Listing.listing_type == filters.listing_type.value)

    if filters.query:
        like = f"%{filters.query.strip()}%"
        query = query.where(or_(Listing.title.ilike(like), Listing.description.ilike(like)))

    if filters.deal_type is not None:
        query = query.where(commercial.deal_type == filters.deal_type.value)

    if filters.commercial_subtype is not None:
        query = query.where(commercial.property_subtype == filters.commercial_subtype.value)

    if filters.shortlet_subtype is not None:
        bedroom_map = {"1_bedroom": 1, "2_bedroom": 2, "3_bedroom": 3}
        bedrooms = bedroom_map.get(filters.shortlet_subtype.value)
        if bedrooms is not None:
            query = query.where(shortlet.bedrooms == bedrooms)
        # "hostel"/"hotel" cannot be filtered until ShortletListing gains a
        # subtype column (see module docstring, gap #3) -- intentionally a
        # no-op rather than raising, per graceful-degradation conventions.

    if filters.min_price is not None or filters.max_price is not None:
        price_conditions = []
        if filters.min_price is not None:
            price_conditions.append(
                or_(
                    commercial.price >= filters.min_price,
                    shortlet.nightly_price >= filters.min_price,
                )
            )
        if filters.max_price is not None:
            price_conditions.append(
                or_(
                    commercial.price <= filters.max_price,
                    shortlet.nightly_price <= filters.max_price,
                )
            )
        query = query.where(and_(*price_conditions))

    if filters.min_size_sqm is not None:
        query = query.where(commercial.size_square_meters >= filters.min_size_sqm)
    if filters.max_size_sqm is not None:
        query = query.where(commercial.size_square_meters <= filters.max_size_sqm)

    # bathrooms -- schema gap #1. Guarded so this never raises AttributeError
    # if the column is absent; becomes a real filter the moment it's added.
    if filters.bathrooms is not None:
        commercial_bathrooms = getattr(commercial, "bathrooms", None)
        shortlet_bathrooms = getattr(shortlet, "bathrooms", None)
        if commercial_bathrooms is not None or shortlet_bathrooms is not None:
            conditions = [
                col == filters.bathrooms
                for col in (commercial_bathrooms, shortlet_bathrooms)
                if col is not None
            ]
            query = query.where(or_(*conditions))
        # else: TODO(schema) -- bathrooms column not yet added; filter is a
        # documented no-op until then (see module docstring gap #1).

    if filters.legal_documents:
        for doc in filters.legal_documents:
            query = query.where(commercial.legal_documents.contains([doc]))

    if filters.amenities:
        for amenity in filters.amenities:
            query = query.where(Listing.amenities.contains([amenity]))

    if filters.verified_only:
        query = query.where(HostAccount.status == "verified")

    if filters.latitude is not None and filters.longitude is not None:
        search_point = func.ST_SetSRID(func.ST_MakePoint(filters.longitude, filters.latitude), 4326)
        search_point = func.CAST(search_point, Geography)
        query = query.where(
            func.ST_DWithin(Listing.location_point, search_point, filters.radius_km * 1000)
        )

    return query, commercial, shortlet


def _apply_sort_and_cursor(
    query: Select,
    commercial: CommercialListing,
    shortlet: ShortletListing,
    filters: SearchFilters,
    cursor: str | None,
    page_size: int,
) -> Select:
    """Cursor-based (keyset) pagination -- never offset/page-number, per
    AGENTS.md. The sort column plus `Listing.id` as a tiebreaker forms a
    total order so pagination is stable even with duplicate sort values."""
    descending = filters.sort_direction.value == "desc"

    if (
        filters.sort_by == SortField.distance
        and filters.latitude is not None
        and filters.longitude is not None
    ):
        search_point = func.ST_SetSRID(func.ST_MakePoint(filters.longitude, filters.latitude), 4326)
        search_point = func.CAST(search_point, Geography)
        sort_expr = func.ST_Distance(Listing.location_point, search_point)
    elif filters.sort_by == SortField.price:
        sort_expr = func.coalesce(commercial.price, shortlet.nightly_price)
    else:
        sort_expr = Listing.created_at

    query = query.order_by(sort_expr.desc() if descending else sort_expr.asc(), Listing.id.asc())

    if cursor:
        last_value_raw, last_id = _decode_cursor(cursor)
        # Proper compound keyset predicate: (sort_expr, id) > (last_value, last_id)
        # in the row's sort direction, so pagination stays correct even when
        # sort_expr has duplicate values across many rows (price/distance
        # ties), not just for the monotonic "newest" case.
        if filters.sort_by == SortField.newest:
            last_value = datetime.fromisoformat(last_value_raw)
        else:
            last_value = float(last_value_raw)

        if descending:
            query = query.where(
                or_(
                    sort_expr < last_value,
                    and_(sort_expr == last_value, Listing.id > last_id),
                )
            )
        else:
            query = query.where(
                or_(
                    sort_expr > last_value,
                    and_(sort_expr == last_value, Listing.id > last_id),
                )
            )

    return query.limit(page_size + 1)


async def search_listings(
    session: AsyncSession, filters: SearchFilters, cursor: str | None, page_size: int
) -> SearchPage:
    """Core FEAT-006/FEAT-007 query. FEAT-031's free-text `filters.query` is
    handled as a plain ILIKE keyword match (the graceful-degradation fallback
    FEAT-031 itself requires) -- see module docstring gap #2 for what a real
    semantic layer would add on top without changing this function's
    contract (it would re-rank/blend, not replace, these results).
    """
    page_size = max(1, min(page_size, MAX_PAGE_SIZE))

    query, commercial, shortlet = _build_base_query(filters)
    query = _apply_sort_and_cursor(query, commercial, shortlet, filters, cursor, page_size)

    result = await session.execute(query)
    rows = result.all()

    has_more = len(rows) > page_size
    rows = rows[:page_size]

    results: list[ListingSearchResult] = []
    distance_km_by_id: dict[str, float] = {}

    if filters.latitude is not None and filters.longitude is not None and rows:
        # Distance is computed inline per-row below via a Python haversine
        # fallback is avoided -- instead we re-select distances in bulk to
        # avoid N+1 ST_Distance calls per row when not already the sort key.
        listing_ids = [row[0].id for row in rows]
        search_point = func.ST_SetSRID(func.ST_MakePoint(filters.longitude, filters.latitude), 4326)
        search_point = func.CAST(search_point, Geography)
        dist_query = select(
            Listing.id, func.ST_Distance(Listing.location_point, search_point)
        ).where(Listing.id.in_(listing_ids))
        dist_rows = (await session.execute(dist_query)).all()
        distance_km_by_id = {
            lid: (meters / 1000.0 if meters is not None else None) for lid, meters in dist_rows
        }

    for listing, commercial, shortlet, host_account in rows:
        is_commercial = listing.listing_type == "commercial"
        bathrooms_value = None
        if is_commercial and commercial is not None:
            bathrooms_value = getattr(commercial, "bathrooms", None)
        elif not is_commercial and shortlet is not None:
            bathrooms_value = getattr(shortlet, "bathrooms", None)

        results.append(
            ListingSearchResult(
                id=listing.id,
                listing_type=ListingTypeFilter(listing.listing_type),
                title=listing.title,
                location_city=listing.location_city,
                location_state=listing.location_state,
                location_address_line=listing.location_address_line,
                latitude=listing.location_latitude,
                longitude=listing.location_longitude,
                distance_km=distance_km_by_id.get(listing.id),
                deal_type=commercial.deal_type if commercial else None,
                price=commercial.price if commercial else None,
                commercial_subtype=commercial.property_subtype if commercial else None,
                size_square_meters=commercial.size_square_meters if commercial else None,
                legal_documents=commercial.legal_documents if commercial else None,
                nightly_price=shortlet.nightly_price if shortlet else None,
                bedrooms=shortlet.bedrooms if shortlet else None,
                amenities=listing.amenities or [],
                is_verified_host=bool(host_account and host_account.status == "verified"),
                primary_image_url=None,  # populated by a follow-up join on ListingImage if needed
                created_at=listing.created_at.isoformat(),
                bathrooms=bathrooms_value,
            )
        )

    next_cursor = None
    if has_more and results:
        last = results[-1]
        if filters.sort_by == SortField.distance:
            sort_value = str(last.distance_km * 1000.0) if last.distance_km is not None else "0"
        elif filters.sort_by == SortField.price:
            sort_value = str(last.price if last.price is not None else last.nightly_price)
        else:
            sort_value = last.created_at
        next_cursor = _encode_cursor(sort_value, last.id)

    return SearchPage(
        results=results,
        next_cursor=next_cursor,
        has_more=has_more,
        degraded_info=SemanticSearchDegradedInfo(
            semantic_ranking_applied=False,
            reason=(
                "FEAT-031 embedding column not yet defined in schema.md/models "
                "-- keyword/filter-only fallback always in effect."
            )
            if filters.query
            else None,
        ),
    )
