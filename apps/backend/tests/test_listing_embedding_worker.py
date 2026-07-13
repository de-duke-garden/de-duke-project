"""Tests for FEAT-031's (re)embedding worker
(app/workers/listing_embedding_worker.py).

Listing carries a PostGIS Geography column (already excluded from the
SQLite test fixture per tests/conftest.py's `_sqlite_safe_tables`, before
this feature even existed) and now also a pgvector Vector column, neither of
which SQLite can create -- so, consistent with the rest of the Listing-table
test surface in this codebase, these tests exercise the worker's query-
building/branching logic against a mocked AsyncSession rather than a live
table, plus the pure `_embedding_input_text` helper directly against a
constructed (never persisted) Listing instance.
"""

from __future__ import annotations

from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock

import pytest

from app.models.listing import Listing
from app.workers.listing_embedding_worker import _embedding_input_text, embed_pending_listings


def _make_listing(**overrides: object) -> Listing:
    defaults = dict(
        host_account_id="host-1",
        listing_type="shortlet",
        title="Cozy 2 Bedroom",
        description="A quiet flat near a school with parking",
        location_latitude=6.5,
        location_longitude=3.3,
        location_address_line="1 Test Street",
        location_city="Lagos",
        location_state="Lagos",
        amenities=["parking", "wifi"],
        status="active",
    )
    defaults.update(overrides)
    return Listing(**defaults)


class TestEmbeddingInputText:
    def test_combines_title_description_location_and_amenities(self) -> None:
        listing = _make_listing()
        text = _embedding_input_text(listing)
        assert "Cozy 2 Bedroom" in text
        assert "quiet flat near a school" in text
        assert "Lagos" in text
        assert "parking" in text
        assert "wifi" in text

    def test_handles_empty_amenities(self) -> None:
        listing = _make_listing(amenities=[])
        text = _embedding_input_text(listing)
        assert "Cozy 2 Bedroom" in text


class TestEmbedPendingListings:
    async def test_embeds_and_commits_pending_listings(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        listing = _make_listing(embedding_updated_at=None)
        session = AsyncMock()
        result_mock = MagicMock()
        result_mock.scalars.return_value.all.return_value = [listing]
        session.execute.return_value = result_mock

        fake_embedding = [0.1, 0.2, 0.3]

        async def _fake_embed_text(text: str, *, timeout_seconds: float) -> list[float]:
            return fake_embedding

        monkeypatch.setattr("app.workers.listing_embedding_worker.embed_text", _fake_embed_text)

        processed = await embed_pending_listings(session, batch_size=10)

        assert processed == 1
        assert listing.description_embedding == fake_embedding
        assert listing.embedding_updated_at is not None
        session.add.assert_called_once_with(listing)
        session.commit.assert_awaited_once()

    async def test_degraded_embedding_call_leaves_listing_untouched_for_retry(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """embed_text returning None (timeout/circuit open/error) must not
        raise, must not mark the listing as embedded, and must not prevent
        it from being retried on the worker's next invocation."""
        listing = _make_listing(embedding_updated_at=None)
        session = AsyncMock()
        result_mock = MagicMock()
        result_mock.scalars.return_value.all.return_value = [listing]
        session.execute.return_value = result_mock

        async def _fake_embed_text(text: str, *, timeout_seconds: float) -> None:
            return None

        monkeypatch.setattr("app.workers.listing_embedding_worker.embed_text", _fake_embed_text)

        processed = await embed_pending_listings(session, batch_size=10)

        assert processed == 1
        assert listing.description_embedding is None
        assert listing.embedding_updated_at is None
        session.add.assert_not_called()
        session.commit.assert_not_awaited()

    async def test_no_pending_listings_is_a_noop(self) -> None:
        session = AsyncMock()
        result_mock = MagicMock()
        result_mock.scalars.return_value.all.return_value = []
        session.execute.return_value = result_mock

        processed = await embed_pending_listings(session, batch_size=10)

        assert processed == 0
        session.commit.assert_not_awaited()

    async def test_stale_embedding_is_reembedded(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """A listing whose embedding predates its last edit
        (embedding_updated_at < updated_at) is exactly the "edited listing
        gets reflected within a few minutes" FEAT-031 AC -- selection of
        such rows is the query built in embed_pending_listings; this test
        exercises the branch where the row IS returned by that query
        (selection itself needs a live Postgres to verify the SQL
        predicate, out of scope here per this module's own docstring)."""
        listing = _make_listing(
            embedding_updated_at=datetime(2020, 1, 1, tzinfo=UTC),
            description_embedding=[0.0, 0.0],
        )
        session = AsyncMock()
        result_mock = MagicMock()
        result_mock.scalars.return_value.all.return_value = [listing]
        session.execute.return_value = result_mock

        new_embedding = [0.9, 0.8]

        async def _fake_embed_text(text: str, *, timeout_seconds: float) -> list[float]:
            return new_embedding

        monkeypatch.setattr("app.workers.listing_embedding_worker.embed_text", _fake_embed_text)

        processed = await embed_pending_listings(session, batch_size=10)

        assert processed == 1
        assert listing.description_embedding == new_embedding
