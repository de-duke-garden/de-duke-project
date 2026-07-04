"""Unit tests for pure listing business logic that doesn't need a live
database -- FEAT-004/005/008.

Integration tests that require a real Postgres+PostGIS instance (listing
CRUD round-trips, `is_listing_available` against real rows) are marked
skipped below with a reason, per AGENTS.md guidance not to fake a DB.
"""

from datetime import date

import pytest

from app.services.listing_service import (
    dates_overlap,
    derive_status_for_new_listing,
    make_location_point_wkt,
)


class TestDeriveStatusForNewListing:
    """FEAT-008 auto-approval rule."""

    def test_owner_goes_to_under_review(self) -> None:
        status_value, reason = derive_status_for_new_listing("owner")
        assert status_value == "under_review"
        assert reason is None

    @pytest.mark.parametrize(
        "host_type", ["agent", "company", "lawyer", "architect", "surveyor"]
    )
    def test_non_owner_types_auto_approve(self, host_type: str) -> None:
        status_value, reason = derive_status_for_new_listing(host_type)
        assert status_value == "active"
        assert reason is None


class TestMakeLocationPointWkt:
    def test_produces_srid_4326_point_lng_lat_order(self) -> None:
        wkt = make_location_point_wkt(latitude=6.5244, longitude=3.3792)
        assert wkt == "SRID=4326;POINT(3.3792 6.5244)"


class TestDatesOverlap:
    def test_overlapping_ranges(self) -> None:
        assert dates_overlap(
            date(2026, 8, 1), date(2026, 8, 5), date(2026, 8, 3), date(2026, 8, 10)
        )

    def test_touching_boundary_counts_as_overlap(self) -> None:
        assert dates_overlap(
            date(2026, 8, 1), date(2026, 8, 5), date(2026, 8, 5), date(2026, 8, 10)
        )

    def test_non_overlapping_ranges(self) -> None:
        assert not dates_overlap(
            date(2026, 8, 1), date(2026, 8, 5), date(2026, 8, 6), date(2026, 8, 10)
        )


@pytest.mark.skip(
    reason=(
        "Requires a live Postgres+PostGIS instance (Listing.location_point "
        "Geography column, Transaction/ShortletListing rows) -- no such "
        "instance is available in this environment. See "
        "app/services/listing_service.py::is_listing_available for the "
        "logic under test; wire this up against a real/test DB in CI."
    )
)
class TestIsListingAvailableIntegration:
    async def test_conflict_from_transaction(self) -> None:
        ...

    async def test_conflict_from_blocked_dates(self) -> None:
        ...
