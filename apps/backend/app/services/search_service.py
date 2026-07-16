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
Wired below (see `_build_cache_key`/`_serialize_page`/`_deserialize_page`)
using the existing thin app/core/cache.py primitives (peek/set_with_ttl) --
only the first page (`cursor is None`) of a free-text (`filters.query`)
search is cached, since that is the "repeated/common search phrase" case
FEAT-031's AC targets; deep-paginated continuations of the same query are
comparatively rare and always re-run against the DB.

RESOLVED SCHEMA GAPS (were flagged during Phase B review, now fixed):
- `bathrooms: int` (indexed) added to both CommercialListing and
  ShortletListing; the filter below queries it directly.
- `subtype: str` (indexed) added to ShortletListing (hostel/hotel); the
  shortlet_subtype filter queries it directly.
- Missing indexes backfilled on app/models/listing.py: Listing.created_at,
  CommercialListing.deal_type/price/size_square_meters,
  ShortletListing.nightly_price, and an explicit GiST index on
  Listing.location_point.

RESOLVED (FEAT-031 embedding column): `Listing.description_embedding` (a
pgvector `Vector` column, HNSW cosine index) now exists -- see
app/models/listing.py and the `c3d4e5f6a7b8` migration --
populated asynchronously by app/workers/listing_embedding_worker.py. Semantic
ranking is implemented below as a *blend*, never a replacement, of the
existing filter/geo/sort-ordered candidate set: `_semantic_rerank` combines
each candidate's original rank position (already reflects geo distance,
price, or recency per `filters.sort_by`) with its cosine similarity to the
query's embedding, 50/50. The query embedding itself is computed with a
bounded timeout + circuit breaker (`embed_text`, embedding_service.py) --
on timeout/unavailability this degrades to the plain keyword/filter-only
ordering already implemented below, and `SemanticSearchDegradedInfo.
semantic_ranking_applied` reports False so callers can tell. Semantic
blending (and its cache) only ever applies to the first page of a free-text
query (`cursor is None`) -- blending changes row order, which would break
keyset pagination's total-order guarantee across pages; subsequent pages of
the same query intentionally fall back to plain ordering. This trade-off is
acceptable for a P2/effort-M feature and is documented rather than silently
made.
- amenities / legal_documents (JSON array columns) -- containment filtering
  (`amenities @> ['parking']`) on a JSON column is not index-friendly at
  Postgres scale; ACTION NEEDED: consider a GIN index if these columns are
  migrated to `ARRAY(String)` or `JSONB` (currently generic `JSON`, which
  GIN cannot index as efficiently as `JSONB`). Flagging rather than silently
  reinterpreting the column type here.
"""

from __future__ import annotations

import base64
import hashlib
import json
from dataclasses import dataclass
from datetime import datetime

from geoalchemy2 import Geography
from sqlalchemy import Select, and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.core import cache
from app.core.config import get_settings
from app.models.host_account import HostAccount
from app.models.listing import CommercialListing, Listing, ListingImage, ShortletListing
from app.schemas.search import (
    ListingSearchResult,
    ListingTypeFilter,
    SearchFilters,
    SemanticSearchDegradedInfo,
    SortField,
)
from app.services.embedding_service import embed_text

DEFAULT_PAGE_SIZE = 20
MAX_PAGE_SIZE = 50
# Upper bound on how many candidates are pulled from the DB before semantic
# reranking narrows back down to the requested page_size -- large enough to
# give the blend meaningful headroom, capped so a popular query never forces
# an unbounded fetch.
MAX_SEMANTIC_CANDIDATES = MAX_PAGE_SIZE * 3


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


def _build_semantic_cache_key(filters: SearchFilters, page_size: int) -> str:
    """Deterministic cache key for a free-text search's first page --
    hashes the full filter set (not just `query`) so two identical phrases
    with different filters/location never collide on the same cached
    result."""
    payload = filters.model_dump(mode="json")
    payload["page_size"] = page_size
    canonical = json.dumps(payload, sort_keys=True)
    digest = hashlib.sha256(canonical.encode()).hexdigest()
    return f"search:semantic:{digest}"


def _serialize_page(page: SearchPage) -> str:
    return json.dumps(
        {
            "results": [r.model_dump(mode="json") for r in page.results],
            "next_cursor": page.next_cursor,
            "has_more": page.has_more,
            "degraded_info": page.degraded_info.model_dump(mode="json"),
        }
    )


def _deserialize_page(raw: str) -> SearchPage:
    data = json.loads(raw)
    return SearchPage(
        results=[ListingSearchResult.model_validate(r) for r in data["results"]],
        next_cursor=data["next_cursor"],
        has_more=data["has_more"],
        degraded_info=SemanticSearchDegradedInfo.model_validate(data["degraded_info"]),
    )


def _blend_semantic_rank(rows: list[tuple], distance_by_id: dict[str, float]) -> list[tuple]:
    """Combines each candidate row's original rank position (already
    reflects filters.sort_by -- geo distance, price, or recency) with its
    cosine similarity to the query embedding, 50/50, and returns rows
    reordered by the combined score (descending). Rows with no embedding
    yet (not in `distance_by_id` -- e.g. a very recently published listing
    the embedding worker hasn't reached yet) get similarity 0.0 rather than
    being dropped, so they still surface via their original rank alone.

    Pure/synchronous and unit-testable in isolation from the DB fetch that
    produces `distance_by_id` (see `_semantic_rerank` below).
    """
    total = len(rows)
    scored: list[tuple[float, int, tuple]] = []
    for index, row in enumerate(rows):
        listing = row[0]
        # 1.0 for the top-ranked candidate, 0.0 for the last, evenly spaced.
        rank_score = 1.0 if total <= 1 else 1.0 - (index / (total - 1))
        distance = distance_by_id.get(listing.id)
        similarity = (1.0 - distance) if distance is not None else 0.0
        combined = 0.5 * rank_score + 0.5 * similarity
        scored.append((combined, index, row))

    # Secondary key = original index keeps ties in their original (already
    # filter/geo/sort-ordered) relative order rather than an arbitrary one.
    scored.sort(key=lambda item: (-item[0], item[1]))
    return [row for _, _, row in scored]


async def _semantic_rerank(
    session: AsyncSession, rows: list[tuple], embedding: list[float]
) -> list[tuple]:
    """Fetches cosine distance (query embedding <-> each candidate's stored
    description_embedding) for `rows` in one bulk query -- avoids an N+1
    round-trip per candidate -- then delegates to `_blend_semantic_rank`."""
    listing_ids = [row[0].id for row in rows]
    dist_query = select(Listing.id, Listing.description_embedding.cosine_distance(embedding)).where(
        Listing.id.in_(listing_ids)
    )
    dist_rows = (await session.execute(dist_query)).all()
    distance_by_id = {lid: distance for lid, distance in dist_rows if distance is not None}
    return _blend_semantic_rank(rows, distance_by_id)


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
        query = query.where(shortlet.subtype == filters.shortlet_subtype.value)

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

    if filters.bathrooms is not None:
        query = query.where(
            or_(commercial.bathrooms == filters.bathrooms, shortlet.bathrooms == filters.bathrooms)
        )

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
    """Core FEAT-006/FEAT-007/FEAT-031 query.

    `filters.query` always drives the plain ILIKE keyword match in
    `_build_base_query` (the graceful-degradation fallback FEAT-031 itself
    requires, and the only thing that ever happens for cursor-paginated
    continuations). On the *first page* of a free-text query, this also
    attempts to blend in semantic ranking: a bounded-timeout, circuit-
    breaker-guarded embedding call (`embed_text`) for the query text, then
    `_semantic_rerank` combines relevance with the existing geo/filter/sort
    order -- never replacing it. Repeated/common first-page queries are
    served from the shared Cache (Redis) instead of recomputing.
    """
    page_size = max(1, min(page_size, MAX_PAGE_SIZE))
    settings = get_settings()

    # Semantic ranking/caching only ever apply to a free-text query's first
    # page -- see module docstring's "RESOLVED (FEAT-031 embedding column)"
    # note for why deeper pages intentionally fall back to plain ordering.
    attempt_semantic = bool(filters.query) and cursor is None

    cache_key: str | None = None
    if attempt_semantic:
        cache_key = _build_semantic_cache_key(filters, page_size)
        cached_raw = await cache.peek(cache_key)
        if cached_raw is not None:
            return _deserialize_page(cached_raw)

    semantic_embedding: list[float] | None = None
    if attempt_semantic:
        semantic_embedding = await embed_text(
            filters.query, timeout_seconds=settings.semantic_search_timeout_seconds
        )

    fetch_limit = page_size
    if attempt_semantic and semantic_embedding is not None:
        # Pull a wider candidate window so reranking has real headroom to
        # surface relevant-but-not-top-ranked-by-filters listings, capped so
        # a popular query never forces an unbounded fetch.
        fetch_limit = min(page_size * 3, MAX_SEMANTIC_CANDIDATES)

    query, commercial, shortlet = _build_base_query(filters)
    query = _apply_sort_and_cursor(query, commercial, shortlet, filters, cursor, fetch_limit)

    result = await session.execute(query)
    rows = result.all()

    semantic_applied = False
    if attempt_semantic and semantic_embedding is not None and rows:
        rows = await _semantic_rerank(session, rows, semantic_embedding)
        semantic_applied = True

    has_more = len(rows) > page_size
    rows = rows[:page_size]

    results: list[ListingSearchResult] = []
    distance_km_by_id: dict[str, float] = {}

    # `primary_image_url` was previously hardcoded to None here with a
    # "populated by a follow-up join if needed" TODO that was never
    # actually done -- every listing card on Home Feed/Search Results
    # (this endpoint's only two callers) rendered the house-silhouette
    # placeholder regardless of whether the listing had photos. Batched
    # (one query for the whole page, not N+1 per row), same pattern as
    # listing_service.list_host_listings' primary_image_by_listing.
    primary_image_by_listing: dict[str, str] = {}
    if rows:
        listing_ids_for_images = [row[0].id for row in rows]
        images_result = await session.execute(
            select(ListingImage.listing_id, ListingImage.image_url)
            .where(ListingImage.listing_id.in_(listing_ids_for_images))
            .where(ListingImage.is_primary == True)  # noqa: E712 -- SQLAlchemy column comparison, not a Python bool check
        )
        primary_image_by_listing = dict(images_result.all())

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
            bathrooms_value = commercial.bathrooms
        elif not is_commercial and shortlet is not None:
            bathrooms_value = shortlet.bathrooms

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
                primary_image_url=primary_image_by_listing.get(listing.id),
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

    if filters.query and not semantic_applied:
        degraded_reason = (
            "Semantic ranking unavailable for this page -- keyword/filter-only "
            "fallback in effect (query embedding timed out/failed, the circuit "
            "breaker is open, or this is a paginated continuation, which always "
            "uses plain ordering; see search_service.py's module docstring)."
        )
    else:
        degraded_reason = None

    page = SearchPage(
        results=results,
        next_cursor=next_cursor,
        has_more=has_more,
        degraded_info=SemanticSearchDegradedInfo(
            semantic_ranking_applied=semantic_applied,
            reason=degraded_reason,
        ),
    )

    if attempt_semantic and cache_key is not None:
        # Cache-aside: only ever written for the (query, filters, page_size)
        # combination just computed above, first page only -- see
        # module docstring. Cached even when degraded, so a temporarily
        # unavailable ranking service doesn't cause every repeated request
        # for the same popular query to each independently retry it.
        await cache.set_with_ttl(
            cache_key, _serialize_page(page), ttl_seconds=settings.semantic_search_cache_ttl_seconds
        )

    return page
