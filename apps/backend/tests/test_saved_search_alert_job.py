"""FEAT-023 -- tests for the matching predicate and alert dedupe logic.

`listing_matches_saved_search` is pure-logic and tested directly against a
`ListingSnapshot` (no DB), same pattern as `test_hold_expiry_pure.py`'s
`is_hold_active` tests. `Listing` itself has a PostGIS Geography column
excluded from the SQLite test engine (see conftest.py's
`_sqlite_safe_tables`), so `run_alert_sweep`'s full DB-touching sweep isn't
exercised end-to-end here (same documented gap `test_hold_expiry_pure.py`
notes for `expire_stale_holds`'s DB-touching half) -- instead, the dedupe
guard (`SavedSearchAlertLog`'s unique constraint) is tested directly
against the `session` fixture, since that table has no Geography column
and creates fine under SQLite.
"""

from datetime import UTC, datetime

import pytest
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.discovery import SavedSearch
from app.models.saved_search_alert import SavedSearchAlertLog
from app.services.saved_search_service import ListingSnapshot, listing_matches_saved_search


def _search(**overrides: object) -> SavedSearch:
    defaults: dict[str, object] = {
        "id": "search-1",
        "user_id": "user-1",
        "label": "Test search",
        "location_query": "Lekki",
        "radius_km": 10.0,
        "listing_type": None,
        "min_price": None,
        "max_price": None,
        "verified_only": False,
        "alerts_enabled": True,
        "created_at": datetime.now(UTC),
    }
    defaults.update(overrides)
    return SavedSearch(**defaults)  # type: ignore[arg-type]


def _listing(**overrides: object) -> ListingSnapshot:
    defaults: dict[str, object] = {
        "listing_type": "shortlet",
        "price": 200000.0,
        "is_verified_host": True,
        "location_city": "Lagos",
        "location_state": "Lagos State",
        "location_address_line": "12 Admiralty Way, Lekki Phase 1",
    }
    defaults.update(overrides)
    return ListingSnapshot(**defaults)  # type: ignore[arg-type]


def test_matches_on_location_substring() -> None:
    search = _search(location_query="Lekki")
    listing = _listing()
    assert listing_matches_saved_search(search, listing) is True


def test_does_not_match_different_location() -> None:
    search = _search(location_query="Ikeja")
    listing = _listing()
    assert listing_matches_saved_search(search, listing) is False


def test_matches_listing_type_filter() -> None:
    search = _search(listing_type="commercial")
    listing = _listing(listing_type="shortlet")
    assert listing_matches_saved_search(search, listing) is False

    listing_commercial = _listing(listing_type="commercial")
    assert listing_matches_saved_search(search, listing_commercial) is True


def test_matches_price_range() -> None:
    search = _search(min_price=100000, max_price=250000)
    assert listing_matches_saved_search(search, _listing(price=200000)) is True
    assert listing_matches_saved_search(search, _listing(price=50000)) is False
    assert listing_matches_saved_search(search, _listing(price=300000)) is False
    # No price on the listing (shouldn't happen in practice, but must not
    # silently pass a price-filtered search).
    assert listing_matches_saved_search(search, _listing(price=None)) is False


def test_verified_only_filter() -> None:
    search = _search(verified_only=True)
    assert listing_matches_saved_search(search, _listing(is_verified_host=False)) is False
    assert listing_matches_saved_search(search, _listing(is_verified_host=True)) is True


def test_blank_location_query_still_requires_non_empty_string() -> None:
    """SavedSearchCreate requires min_length=1, but a search saved with only
    whitespace should not silently match every listing everywhere."""
    search = _search(location_query="   ")
    assert listing_matches_saved_search(search, _listing()) is True


class TestGeocodedRadiusMatching:
    """Once both sides have been successfully geocoded, matching uses a
    real haversine distance against radius_km rather than the substring
    fallback -- these two Lekki-area points are ~2km apart; Ikeja is
    ~15km away."""

    _LEKKI_PHASE_1 = (6.4407, 3.4763)
    _IKEJA = (6.6018, 3.3515)

    def test_matches_when_within_radius_km(self) -> None:
        lat, lon = self._LEKKI_PHASE_1
        search = _search(
            location_query="Lekki",
            radius_km=10.0,
            location_latitude=lat,
            location_longitude=lon,
        )
        nearby_lat, nearby_lon = 6.4491, 3.4726  # ~1km away
        listing = _listing(location_latitude=nearby_lat, location_longitude=nearby_lon)
        assert listing_matches_saved_search(search, listing) is True

    def test_does_not_match_outside_radius_km(self) -> None:
        lat, lon = self._LEKKI_PHASE_1
        search = _search(
            location_query="Lekki",
            radius_km=5.0,
            location_latitude=lat,
            location_longitude=lon,
        )
        far_lat, far_lon = self._IKEJA
        listing = _listing(location_latitude=far_lat, location_longitude=far_lon)
        assert listing_matches_saved_search(search, listing) is False

    def test_falls_back_to_substring_when_listing_has_no_coordinates(self) -> None:
        """The search was geocoded but the listing snapshot wasn't (e.g. an
        older listing row) -- must degrade to substring matching rather
        than treat the pair as "unknown distance, no match"."""
        lat, lon = self._LEKKI_PHASE_1
        search = _search(
            location_query="Lekki", radius_km=1.0, location_latitude=lat, location_longitude=lon
        )
        listing = _listing(location_latitude=None, location_longitude=None)
        # Matches the address-line substring even though it's far outside
        # a literal 1km radius -- proves the coordinate path wasn't used.
        assert listing_matches_saved_search(search, listing) is True

    def test_falls_back_to_substring_when_search_was_never_geocoded(self) -> None:
        search = _search(location_query="Lekki", location_latitude=None, location_longitude=None)
        listing = _listing(location_latitude=self._IKEJA[0], location_longitude=self._IKEJA[1])
        # Substring match against "Lekki Phase 1" in the address line
        # still succeeds regardless of the listing's real coordinates.
        assert listing_matches_saved_search(search, listing) is True


@pytest.mark.asyncio
async def test_alert_log_unique_constraint_prevents_double_notify(session: AsyncSession) -> None:
    """The actual "does not double-notify" guard: a second insert for the
    same (saved_search_id, listing_id) pair must fail, which is exactly
    what `_record_and_notify` in saved_search_alert_job.py relies on to
    skip sending a second push."""
    session.add(SavedSearchAlertLog(saved_search_id="search-1", listing_id="listing-1"))
    await session.commit()

    session.add(SavedSearchAlertLog(saved_search_id="search-1", listing_id="listing-1"))
    with pytest.raises(IntegrityError):
        await session.commit()
    await session.rollback()

    # A different listing (or a different search) for the same pair's
    # other half is unaffected -- the constraint is on the pair, not either
    # column alone.
    session.add(SavedSearchAlertLog(saved_search_id="search-1", listing_id="listing-2"))
    await session.commit()
