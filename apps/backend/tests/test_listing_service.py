"""Unit tests for pure listing business logic that doesn't need a live
database -- FEAT-004/005/008.

Integration tests that require a real Postgres+PostGIS instance (listing
CRUD round-trips, `is_listing_available` against real rows) are marked
skipped below with a reason, per AGENTS.md guidance not to fake a DB.
"""

from datetime import date

import pytest

from app.models.host_account import HostAccount
from app.models.listing import Listing
from app.services.listing_service import (
    dates_overlap,
    derive_status_for_new_listing,
    listing_to_dict,
    make_location_point_wkt,
)


class TestDeriveStatusForNewListing:
    """FEAT-008 auto-approval rule."""

    def test_owner_goes_to_under_review(self) -> None:
        status_value, reason = derive_status_for_new_listing("owner")
        assert status_value == "under_review"
        assert reason is None

    @pytest.mark.parametrize("host_type", ["agent", "company", "lawyer", "architect", "surveyor"])
    def test_non_owner_types_auto_approve(self, host_type: str) -> None:
        status_value, reason = derive_status_for_new_listing(host_type)
        assert status_value == "active"
        assert reason is None


class TestMakeLocationPointWkt:
    def test_produces_srid_4326_point_lng_lat_order(self) -> None:
        wkt = make_location_point_wkt(latitude=6.5244, longitude=3.3792)
        assert wkt == "SRID=4326;POINT(3.3792 6.5244)"


class TestListingToDictHostFields:
    """FEAT-042: Listing Detail's Host Profile card / Admin Chat Oversight
    property context both need the owning host's bio/photo/type from
    GET /listings/:id -- these fields don't touch the DB (in-memory model
    instances only), so they're covered here rather than in an
    integration test the PostGIS-only `listings` table can't run under
    SQLite (see conftest.py's `_sqlite_safe_tables`)."""

    def _listing(self) -> Listing:
        return Listing(
            host_account_id="host-1",
            listing_type="shortlet",
            title="Test Listing",
            description="A place to stay.",
            location_latitude=6.5,
            location_longitude=3.3,
            location_address_line="1 Test Close",
            location_city="Lagos",
            location_state="Lagos",
        )

    def test_includes_host_bio_photo_and_type_when_host_account_given(self) -> None:
        host_account = HostAccount(
            user_id="user-1",
            host_type="owner",
            host_photo_url="https://example.com/host.jpg",
            bio="A friendly, verified host.",
        )
        out = listing_to_dict(self._listing(), images=[], host_account=host_account)
        assert out["host_bio"] == "A friendly, verified host."
        assert out["host_photo_url"] == "https://example.com/host.jpg"
        assert out["host_type"] == "owner"

    def test_host_fields_are_none_when_host_account_omitted(self) -> None:
        """Defensive default -- shouldn't occur for a live listing (a
        HostAccount is required to create one), but must never crash."""
        out = listing_to_dict(self._listing(), images=[])
        assert out["host_bio"] is None
        assert out["host_photo_url"] is None
        assert out["host_type"] is None


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
    async def test_conflict_from_transaction(self) -> None: ...

    async def test_conflict_from_blocked_dates(self) -> None: ...
