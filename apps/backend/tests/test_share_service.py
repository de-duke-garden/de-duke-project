"""Tests for app/services/share_service.py -- FEAT-020 (Shareable Listing
Summary for Internal Approval).

Same rationale as test_moderation_service.py: `Listing` has a PostGIS
Geography column excluded from the SQLite test harness, so these tests use
a fake AsyncSession that dispatches `execute(select(Model)...)` results by
model class rather than a real table-backed session.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from app.models.discovery import ShareableSummary
from app.models.host_account import HostAccount
from app.models.listing import CommercialListing, Listing, ListingMedia, ShortletListing
from app.services import share_service


class _FakeScalarResult:
    def __init__(self, value):
        self._value = value

    def scalar_one_or_none(self):
        return self._value


class FakeSession:
    """Dispatches `execute()` results keyed by the queried model class,
    inferred from the Select statement's `column_descriptions`."""

    def __init__(self, by_model: dict[type, object]) -> None:
        self._by_model = by_model
        self.added: list = []
        self.commit = AsyncMock()

    async def execute(self, stmt):
        model = stmt.column_descriptions[0]["type"]
        return _FakeScalarResult(self._by_model.get(model))

    def add(self, obj) -> None:
        self.added.append(obj)

    async def refresh(self, obj) -> None:  # noqa: ARG002 -- no-op, obj already fully populated
        return None


def _listing(**overrides) -> SimpleNamespace:
    defaults = dict(
        id="listing-1",
        host_account_id="host-account-1",
        listing_type="commercial",
        title="Sunny Office Suite",
        location_city="Lagos",
        location_state="Lagos",
        location_address_line="1 Broad Street",
        status="active",
    )
    defaults.update(overrides)
    return SimpleNamespace(**defaults)


class TestCreateShare:
    @pytest.mark.asyncio
    async def test_creates_share_with_default_expiry(self) -> None:
        listing = _listing()
        session = FakeSession({Listing: listing})

        share = await share_service.create_share(
            session, listing_id="listing-1", created_by_id="user-1"
        )

        assert share.listing_id == "listing-1"
        assert share.created_by_id == "user-1"
        assert share.is_revoked is False
        assert share.share_token  # non-empty, unguessable token
        assert share.expires_at > datetime.now(UTC)
        session.commit.assert_awaited()

    @pytest.mark.asyncio
    async def test_raises_when_listing_missing(self) -> None:
        session = FakeSession({Listing: None})
        with pytest.raises(share_service.ShareNotFoundError):
            await share_service.create_share(session, listing_id="missing", created_by_id="user-1")

    @pytest.mark.asyncio
    async def test_two_calls_produce_different_tokens(self) -> None:
        listing = _listing()
        session = FakeSession({Listing: listing})

        share_a = await share_service.create_share(
            session, listing_id="listing-1", created_by_id="user-1"
        )
        share_b = await share_service.create_share(
            session, listing_id="listing-1", created_by_id="user-1"
        )

        assert share_a.share_token != share_b.share_token


class TestRevokeShare:
    @pytest.mark.asyncio
    async def test_owner_can_revoke(self) -> None:
        share = ShareableSummary(
            listing_id="listing-1", created_by_id="user-1", share_token="tok-1"
        )
        session = FakeSession({ShareableSummary: share})

        result = await share_service.revoke_share(
            session, share_token="tok-1", requesting_user_id="user-1"
        )

        assert result.is_revoked is True
        session.commit.assert_awaited()

    @pytest.mark.asyncio
    async def test_non_owner_forbidden(self) -> None:
        share = ShareableSummary(
            listing_id="listing-1", created_by_id="user-1", share_token="tok-1"
        )
        session = FakeSession({ShareableSummary: share})

        with pytest.raises(share_service.ShareForbiddenError):
            await share_service.revoke_share(
                session, share_token="tok-1", requesting_user_id="someone-else"
            )
        assert share.is_revoked is False

    @pytest.mark.asyncio
    async def test_missing_token_raises_not_found(self) -> None:
        session = FakeSession({ShareableSummary: None})
        with pytest.raises(share_service.ShareNotFoundError):
            await share_service.revoke_share(
                session, share_token="does-not-exist", requesting_user_id="user-1"
            )


class TestIsExpired:
    def test_no_expiry_never_expires(self) -> None:
        share = ShareableSummary(
            listing_id="l", created_by_id="u", share_token="t", expires_at=None
        )
        assert share_service.is_expired(share) is False

    def test_future_expiry_not_expired(self) -> None:
        share = ShareableSummary(
            listing_id="l",
            created_by_id="u",
            share_token="t",
            expires_at=datetime.now(UTC) + timedelta(days=1),
        )
        assert share_service.is_expired(share) is False

    def test_past_expiry_is_expired(self) -> None:
        share = ShareableSummary(
            listing_id="l",
            created_by_id="u",
            share_token="t",
            expires_at=datetime.now(UTC) - timedelta(seconds=1),
        )
        assert share_service.is_expired(share) is True


class TestResolvePublicSummary:
    @pytest.mark.asyncio
    async def test_not_found_when_token_missing(self) -> None:
        session = FakeSession({ShareableSummary: None})
        outcome, summary = await share_service.resolve_public_summary(session, share_token="ghost")
        assert outcome == "not_found"
        assert summary is None

    @pytest.mark.asyncio
    async def test_revoked_blocks_access(self) -> None:
        share = ShareableSummary(
            listing_id="listing-1", created_by_id="u", share_token="t", is_revoked=True
        )
        session = FakeSession({ShareableSummary: share})
        outcome, summary = await share_service.resolve_public_summary(session, share_token="t")
        assert outcome == "revoked"
        assert summary is None

    @pytest.mark.asyncio
    async def test_expired_blocks_access(self) -> None:
        share = ShareableSummary(
            listing_id="listing-1",
            created_by_id="u",
            share_token="t",
            expires_at=datetime.now(UTC) - timedelta(days=1),
        )
        session = FakeSession({ShareableSummary: share})
        outcome, summary = await share_service.resolve_public_summary(session, share_token="t")
        assert outcome == "expired"
        assert summary is None

    @pytest.mark.asyncio
    async def test_valid_token_returns_commercial_summary(self) -> None:
        share = ShareableSummary(
            listing_id="listing-1",
            created_by_id="u",
            share_token="t",
            expires_at=datetime.now(UTC) + timedelta(days=1),
        )
        listing = _listing(listing_type="commercial", status="active")
        host_account = SimpleNamespace(id="host-account-1", status="verified")
        commercial = SimpleNamespace(
            deal_type="lease",
            price=500000.0,
            property_subtype="office",
            size_square_meters=120.0,
            bathrooms=2,
            possession_period_days=365,
        )
        session = FakeSession(
            {
                ShareableSummary: share,
                Listing: listing,
                HostAccount: host_account,
                CommercialListing: commercial,
                ListingMedia: SimpleNamespace(media_url="https://cdn.example/img.jpg"),
            }
        )

        outcome, summary = await share_service.resolve_public_summary(session, share_token="t")

        assert outcome == "ok"
        assert summary["listing_id"] == "listing-1"
        assert summary["price"] == 500000.0
        assert summary["price_label"] == "lease"
        assert summary["verification_status"] == "verified"
        assert summary["listing_is_active"] is True
        assert summary["primary_image_url"] == "https://cdn.example/img.jpg"
        assert any("office" in term for term in summary["key_terms"])

    @pytest.mark.asyncio
    async def test_unverified_host_reported_correctly(self) -> None:
        share = ShareableSummary(
            listing_id="listing-1",
            created_by_id="u",
            share_token="t",
            expires_at=None,
        )
        listing = _listing(listing_type="shortlet", status="unpublished")
        host_account = SimpleNamespace(id="host-account-1", status="in_review")
        shortlet = SimpleNamespace(
            nightly_price=15000.0, bedrooms=2, bathrooms=1, minimum_stay_nights=2
        )
        session = FakeSession(
            {
                ShareableSummary: share,
                Listing: listing,
                HostAccount: host_account,
                ShortletListing: shortlet,
                ListingMedia: None,
            }
        )

        outcome, summary = await share_service.resolve_public_summary(session, share_token="t")

        assert outcome == "ok"
        assert summary["verification_status"] == "unverified"
        # Listing unpublished since the link was generated -- still shown,
        # but flagged inactive rather than treated as not_found (Screen 18
        # "Listing No Longer Active" state / user_flow.md Flow 4 Alt Path D).
        assert summary["listing_is_active"] is False
        assert summary["price_label"] == "per night"
