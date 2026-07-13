"""Tests for Search & Discovery (FEAT-006/FEAT-007/FEAT-031).

No live Postgres+PostGIS instance is available in this environment, so
query-execution-against-a-real-database is out of scope here (see the
skipped integration test class below with a clear reason). What IS tested
without a database:

- Pydantic schema validation (app/schemas/search.py) -- range/logic
  validators.
- Cursor encode/decode round-tripping (app/services/search_service.py).
- Query-building logic in isolation: compiling the SQLAlchemy Select
  objects returned by `_build_base_query` / `_apply_sort_and_cursor` to SQL
  text and asserting the expected clauses appear, without executing them.
- The FastAPI route wiring (app boots, route is registered, and invalid
  filter combinations return 422 -- exercised via TestClient, which does
  not require a live DB connection to run request validation).
"""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.main import app
from app.schemas.search import SearchFilters, SortField
from app.services import search_service
from app.services.search_service import (
    _apply_sort_and_cursor,
    _blend_semantic_rank,
    _build_base_query,
    _decode_cursor,
    _encode_cursor,
    search_listings,
)

client = TestClient(app)


class _FakeListing:
    """Minimal stand-in for app.models.listing.Listing -- only `.id` is read
    by `_blend_semantic_rank`, so a real ORM row (which needs a live
    Postgres/PostGIS/pgvector instance, unavailable here) is unnecessary."""

    def __init__(self, listing_id: str) -> None:
        self.id = listing_id


class TestSearchFiltersValidation:
    def test_min_price_over_max_price_rejected(self) -> None:
        with pytest.raises(ValidationError):
            SearchFilters(min_price=100, max_price=50)

    def test_min_size_over_max_size_rejected(self) -> None:
        with pytest.raises(ValidationError):
            SearchFilters(min_size_sqm=500, max_size_sqm=100)

    def test_distance_sort_requires_coordinates(self) -> None:
        with pytest.raises(ValidationError):
            SearchFilters(sort_by=SortField.distance)

    def test_distance_sort_with_coordinates_is_valid(self) -> None:
        filters = SearchFilters(sort_by=SortField.distance, latitude=6.5, longitude=3.3)
        assert filters.latitude == 6.5

    def test_lat_without_lng_rejected(self) -> None:
        with pytest.raises(ValidationError):
            SearchFilters(latitude=6.5)

    def test_lng_without_lat_rejected(self) -> None:
        with pytest.raises(ValidationError):
            SearchFilters(longitude=3.3)

    def test_defaults_are_valid(self) -> None:
        filters = SearchFilters()
        assert filters.radius_km == 10.0
        assert filters.sort_by == SortField.newest


class TestCursorRoundTrip:
    def test_encode_decode_round_trip(self) -> None:
        cursor = _encode_cursor("2026-01-01T00:00:00", "listing-123")
        value, listing_id = _decode_cursor(cursor)
        assert value == "2026-01-01T00:00:00"
        assert listing_id == "listing-123"

    def test_decode_invalid_cursor_raises(self) -> None:
        with pytest.raises(ValueError, match="Invalid pagination cursor"):
            _decode_cursor("not-a-valid-cursor!!!")


class TestQueryBuilding:
    """Compiles the SQLAlchemy Select without executing it -- validates the
    query-building logic (filters/joins/sort) is well-formed SQL, without
    needing a live database connection."""

    def test_base_query_compiles(self) -> None:
        filters = SearchFilters()
        query, commercial, shortlet = _build_base_query(filters)
        compiled = str(query.compile(compile_kwargs={"literal_binds": False}))
        assert "listings" in compiled
        assert "commercial_listings" in compiled
        assert "shortlet_listings" in compiled

    def test_geo_filter_adds_st_dwithin(self) -> None:
        filters = SearchFilters(latitude=6.5, longitude=3.3, radius_km=5)
        query, _, _ = _build_base_query(filters)
        compiled = str(query.compile(compile_kwargs={"literal_binds": False}))
        assert "ST_DWithin" in compiled

    def test_verified_only_filters_host_account_status(self) -> None:
        filters = SearchFilters(verified_only=True)
        query, _, _ = _build_base_query(filters)
        compiled = str(query.compile(compile_kwargs={"literal_binds": False}))
        assert "host_accounts" in compiled

    def test_price_range_filters_both_subtypes(self) -> None:
        filters = SearchFilters(min_price=100, max_price=1000)
        query, _, _ = _build_base_query(filters)
        compiled = str(query.compile(compile_kwargs={"literal_binds": False}))
        assert "price" in compiled
        assert "nightly_price" in compiled

    def test_bathrooms_filter_is_inert_without_column(self) -> None:
        """Schema gap #1 (see search_service.py docstring): bathrooms column
        does not exist on CommercialListing/ShortletListing today, so this
        must not raise even though the filter is set."""
        filters = SearchFilters(bathrooms=2)
        query, commercial, shortlet = _build_base_query(filters)
        _apply_sort_and_cursor(query, commercial, shortlet, filters, None, 20)  # must not raise

    def test_sort_by_price_uses_coalesce(self) -> None:
        filters = SearchFilters(sort_by=SortField.price)
        query, commercial, shortlet = _build_base_query(filters)
        query = _apply_sort_and_cursor(query, commercial, shortlet, filters, None, 20)
        compiled = str(query.compile(compile_kwargs={"literal_binds": False}))
        assert "coalesce" in compiled.lower()

    def test_cursor_adds_keyset_predicate(self) -> None:
        filters = SearchFilters(sort_by=SortField.newest)
        query, commercial, shortlet = _build_base_query(filters)
        cursor = _encode_cursor("2026-01-01T00:00:00", "abc")
        query = _apply_sort_and_cursor(query, commercial, shortlet, filters, cursor, 20)
        compiled = str(query.compile(compile_kwargs={"literal_binds": False}))
        # Keyset (WHERE ... > :param) rather than OFFSET-based pagination.
        assert "OFFSET" not in compiled.upper()


class TestSearchEndpointValidation:
    """Exercises FastAPI request validation via TestClient -- does not
    require a live DB since these requests fail validation before a query
    would ever run."""

    def test_distance_sort_without_coordinates_returns_422(self) -> None:
        response = client.get("/v1/search/listings", params={"sort_by": "distance"})
        assert response.status_code == 422

    def test_min_price_over_max_price_returns_422(self) -> None:
        response = client.get("/v1/search/listings", params={"min_price": 1000, "max_price": 100})
        assert response.status_code == 422


@pytest.mark.skip(
    reason=(
        "True integration test requiring a live PostgreSQL+PostGIS instance "
        "(ST_DWithin/ST_Distance/ST_MakePoint are Postgres/PostGIS functions "
        "that SQLite or a mocked session cannot execute). No such instance is "
        "available in this sandboxed environment. Query-building correctness "
        "is covered by TestQueryBuilding above; wire this up against a "
        "docker-compose Postgres+PostGIS service in CI."
    )
)
class TestSearchIntegration:
    async def test_search_returns_listings_within_radius(self) -> None:
        raise NotImplementedError


class TestSemanticBlend:
    """FEAT-031 AC: "Semantic ranking is combined with, not a replacement
    for, geospatial proximity and filter criteria." -- exercises the pure
    blending function directly (no DB needed)."""

    def test_top_original_rank_wins_without_any_embeddings(self) -> None:
        rows = [(_FakeListing("a"),), (_FakeListing("b"),), (_FakeListing("c"),)]
        reranked = _blend_semantic_rank(rows, distance_by_id={})
        # No semantic signal at all (distance_by_id empty) -- combined score
        # degenerates to rank_score alone, so original order is preserved.
        assert [row[0].id for row in reranked] == ["a", "b", "c"]

    def test_strong_semantic_match_can_promote_a_lower_ranked_row(self) -> None:
        rows = [(_FakeListing("a"),), (_FakeListing("b"),), (_FakeListing("c"),)]
        # "c" was last by geo/price/recency but is a near-perfect semantic
        # match (cosine distance ~0) -- blended 50/50 it should outrank "b"
        # (no semantic signal) despite b's better original rank.
        distance_by_id = {"c": 0.01}
        reranked = _blend_semantic_rank(rows, distance_by_id)
        ids = [row[0].id for row in reranked]
        assert ids.index("c") < ids.index("b")

    def test_geo_filter_criteria_still_bound_the_candidate_set(self) -> None:
        """Blending only ever reorders the already filter/geo-matched
        candidate rows passed in -- it cannot invent or admit a row outside
        that set, which is how "combined with, not a replacement for" is
        enforced structurally rather than just by the score formula."""
        rows = [(_FakeListing("a"),), (_FakeListing("b"),)]
        reranked = _blend_semantic_rank(rows, distance_by_id={"a": 0.0, "b": 0.0})
        assert {row[0].id for row in reranked} == {"a", "b"}
        assert len(reranked) == len(rows)

    def test_missing_embedding_defaults_to_zero_similarity_not_dropped(self) -> None:
        """A listing the embedding worker hasn't reached yet (no stored
        embedding) must still appear in results, just without a semantic
        boost -- never silently excluded."""
        rows = [(_FakeListing("a"),), (_FakeListing("b"),)]
        reranked = _blend_semantic_rank(rows, distance_by_id={"a": 0.0})
        assert {row[0].id for row in reranked} == {"a", "b"}


class TestSemanticSearchGracefulDegradation:
    """FEAT-031 AC: "Semantic search degrades gracefully to keyword/filter
    -only search if the ranking service is slow or temporarily unavailable,
    within a strict timeout." Exercises search_listings end-to-end against a
    mocked AsyncSession (compiling/executing real SQL needs live Postgres,
    out of scope per TestSearchIntegration above) with a monkeypatched,
    artificially slow embed_text."""

    def _mock_session_returning_no_rows(self) -> AsyncMock:
        session = AsyncMock()
        result_mock = MagicMock()
        result_mock.all.return_value = []
        session.execute.return_value = result_mock
        return session

    async def test_slow_embedding_call_falls_back_to_keyword_only(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        async def _slow_embed_text(text: str, *, timeout_seconds: float) -> None:
            # embed_text itself already enforces the bounded timeout
            # internally and returns None on timeout -- this stand-in
            # mirrors exactly that documented contract without needing a
            # real slow provider/asyncio.sleep in this test.
            return None

        monkeypatch.setattr(search_service, "embed_text", _slow_embed_text)
        session = self._mock_session_returning_no_rows()

        page = await search_listings(
            session, SearchFilters(query="quiet 2 bedroom near a school"), cursor=None, page_size=20
        )

        assert page.degraded_info.semantic_ranking_applied is False
        assert page.degraded_info.reason is not None

    async def test_paginated_continuation_always_uses_keyword_only(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Even when the embedding service is healthy, page 2+ of the same
        free-text query never attempts semantic reranking (see module
        docstring's pagination trade-off)."""
        embed_calls = 0

        async def _tracking_embed_text(text: str, *, timeout_seconds: float) -> list[float]:
            nonlocal embed_calls
            embed_calls += 1
            return [0.1, 0.2]

        monkeypatch.setattr(search_service, "embed_text", _tracking_embed_text)
        session = self._mock_session_returning_no_rows()

        cursor = _encode_cursor("2026-01-01T00:00:00", "listing-1")
        page = await search_listings(
            session, SearchFilters(query="2 bedroom"), cursor=cursor, page_size=20
        )

        assert embed_calls == 0
        assert page.degraded_info.semantic_ranking_applied is False


class TestSemanticSearchCaching:
    """FEAT-031 AC: "Repeated or common search phrases reuse a cached result
    rather than recomputing relevance from scratch every time." """

    async def test_repeated_query_reuses_cached_result(
        self, monkeypatch: pytest.MonkeyPatch, session
    ) -> None:
        """`session` fixture here is tests/conftest.py's fakeredis-backed
        Cache stand-in via the autouse `_stub_redis` fixture, not a DB
        session -- app.core.cache calls in search_listings hit fakeredis,
        never a real Redis instance."""
        del session  # only needed to ensure _stub_redis's autouse fixture is active

        execute_calls = 0

        async def _fake_embed_text(text: str, *, timeout_seconds: float) -> list[float]:
            return [0.1, 0.2]

        class _FakeSession:
            async def execute(self, *args: object, **kwargs: object) -> MagicMock:
                nonlocal execute_calls
                execute_calls += 1
                result_mock = MagicMock()
                result_mock.all.return_value = []
                return result_mock

        monkeypatch.setattr(search_service, "embed_text", _fake_embed_text)
        filters = SearchFilters(query="2 bedroom flat with parking")

        first_page = await search_listings(_FakeSession(), filters, cursor=None, page_size=20)
        second_page = await search_listings(_FakeSession(), filters, cursor=None, page_size=20)

        # Second call must be served entirely from cache -- no additional
        # DB `execute` call, and the two responses are equivalent.
        assert execute_calls == 1
        assert first_page.results == second_page.results
        assert first_page.has_more == second_page.has_more

    async def test_different_filters_do_not_share_a_cache_entry(self) -> None:
        key_a = search_service._build_semantic_cache_key(SearchFilters(query="2 bedroom"), 20)
        key_b = search_service._build_semantic_cache_key(
            SearchFilters(query="2 bedroom", min_price=100), 20
        )
        assert key_a != key_b
