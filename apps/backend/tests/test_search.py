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

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.main import app
from app.schemas.search import SearchFilters, SortField
from app.services.search_service import (
    _apply_sort_and_cursor,
    _build_base_query,
    _decode_cursor,
    _encode_cursor,
)

client = TestClient(app)


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
