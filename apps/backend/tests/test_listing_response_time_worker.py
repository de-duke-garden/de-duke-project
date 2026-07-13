"""Tests for FEAT-019's average-response-time materialization worker."""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.firestore_models import ChatMessage
from app.models.listing import Listing
from app.services.chat_service import ChatServiceUnavailableError
from app.workers import listing_response_time_worker as worker


def _msg(*, sender_role: str | None, minutes_offset: int) -> ChatMessage:
    base = datetime(2026, 1, 1, tzinfo=UTC)
    return ChatMessage(
        id=f"msg-{minutes_offset}-{sender_role}",
        conversation_id="conv-1",
        sender_id="user-1",
        sender_role=sender_role,
        message_type="text",
        body="hi",
        delivery_status="sent",
        sent_at=base + timedelta(minutes=minutes_offset),
    )


class TestAverageFirstResponseMinutes:
    def test_single_client_message_then_reply(self) -> None:
        messages = [
            _msg(sender_role="client", minutes_offset=0),
            _msg(sender_role="property_management", minutes_offset=10),
        ]
        assert worker.average_first_response_minutes(messages) == 10.0

    def test_averages_across_multiple_pairs(self) -> None:
        messages = [
            _msg(sender_role="client", minutes_offset=0),
            _msg(sender_role="property_management", minutes_offset=10),
            _msg(sender_role="client", minutes_offset=20),
            _msg(sender_role="deduke_staff", minutes_offset=40),
        ]
        # gaps: 10 and 20 -> average 15
        assert worker.average_first_response_minutes(messages) == 15.0

    def test_a_reply_is_never_double_counted(self) -> None:
        messages = [
            _msg(sender_role="client", minutes_offset=0),
            _msg(sender_role="client", minutes_offset=5),
            _msg(sender_role="property_management", minutes_offset=10),
        ]
        # Only the most recent pending client message (at minute 5) is
        # resolved by the reply at minute 10 -- one gap of 5 minutes, not two.
        assert worker.average_first_response_minutes(messages) == 5.0

    def test_system_messages_never_count_as_a_reply(self) -> None:
        messages = [
            _msg(sender_role="client", minutes_offset=0),
            _msg(sender_role=None, minutes_offset=1),
            _msg(sender_role="property_management", minutes_offset=10),
        ]
        assert worker.average_first_response_minutes(messages) == 10.0

    def test_no_reply_yet_returns_none(self) -> None:
        messages = [_msg(sender_role="client", minutes_offset=0)]
        assert worker.average_first_response_minutes(messages) is None

    def test_empty_conversation_returns_none(self) -> None:
        assert worker.average_first_response_minutes([]) is None


class TestAverageResponseTimeForListing:
    @pytest.mark.asyncio
    async def test_returns_none_when_firestore_unconfigured(self) -> None:
        with patch.object(
            worker,
            "_get_firestore_client",
            side_effect=ChatServiceUnavailableError("not configured"),
        ):
            result = await worker._average_response_time_for_listing(
                "listing-1", range_start=date(2026, 1, 1), range_end=date(2026, 1, 31)
            )
        assert result is None

    @pytest.mark.asyncio
    async def test_averages_across_conversations(self) -> None:
        def _make_conversation_doc(gap_minutes: int):
            messages = [
                _msg(sender_role="client", minutes_offset=0),
                _msg(sender_role="property_management", minutes_offset=gap_minutes),
            ]
            message_docs = []
            for m in messages:
                doc = MagicMock()
                doc.id = m.id
                doc.to_dict.return_value = {
                    "conversationId": "conv-1",
                    "senderId": m.sender_id,
                    "senderRole": m.sender_role,
                    "messageType": m.message_type,
                    "body": m.body,
                    "deliveryStatus": m.delivery_status,
                    "sentAt": m.sent_at,
                }
                message_docs.append(doc)

            messages_collection = MagicMock()
            messages_collection.order_by.return_value.stream.return_value = message_docs

            conversation_ref = MagicMock()
            conversation_ref.collection.return_value = messages_collection

            conversation_doc = MagicMock()
            conversation_doc.reference = conversation_ref
            return conversation_doc

        conversation_docs = [_make_conversation_doc(10), _make_conversation_doc(20)]

        fake_query = MagicMock()
        fake_query.where.return_value = fake_query
        fake_query.stream.return_value = conversation_docs

        fake_collection = MagicMock()
        fake_collection.where.return_value = fake_query

        fake_client = MagicMock()
        fake_client.collection.return_value = fake_collection

        with patch.object(worker, "_get_firestore_client", return_value=fake_client):
            result = await worker._average_response_time_for_listing(
                "listing-1", range_start=date(2026, 1, 1), range_end=date(2026, 1, 31)
            )

        assert result == 15.0

    @pytest.mark.asyncio
    async def test_returns_none_when_no_conversations(self) -> None:
        fake_query = MagicMock()
        fake_query.where.return_value = fake_query
        fake_query.stream.return_value = []

        fake_collection = MagicMock()
        fake_collection.where.return_value = fake_query

        fake_client = MagicMock()
        fake_client.collection.return_value = fake_collection

        with patch.object(worker, "_get_firestore_client", return_value=fake_client):
            result = await worker._average_response_time_for_listing(
                "listing-1", range_start=date(2026, 1, 1), range_end=date(2026, 1, 31)
            )

        assert result is None


def _make_listing(**overrides: object) -> Listing:
    # Listing carries a PostGIS Geography column SQLite can't create (see
    # test_listing_embedding_worker.py's module docstring for the same
    # constraint) -- constructed but never persisted, exercised against a
    # mocked AsyncSession instead of a live table, consistent with that
    # module's own test approach.
    defaults: dict[str, object] = dict(
        id="listing-1",
        host_account_id="host-account-1",
        listing_type="commercial",
        title="Test listing",
        description="A quiet 2-bedroom",
        location_city="Lagos",
        location_state="Lagos",
        location_address_line="1 Test Street",
        status="active",
        view_count=10,
        inquiry_count=3,
    )
    defaults.update(overrides)
    return Listing(**defaults)


def _result_with_scalars_all(rows: list) -> MagicMock:
    result = MagicMock()
    result.scalars.return_value.all.return_value = rows
    return result


def _result_with_scalars_first(row) -> MagicMock:  # noqa: ANN001
    result = MagicMock()
    result.scalars.return_value.first.return_value = row
    return result


class TestRefreshListingResponseTimes:
    @pytest.mark.asyncio
    async def test_writes_a_snapshot_per_canonical_range(self) -> None:
        listing = _make_listing()
        session = AsyncMock()
        # 1st execute: the Listing select. Every subsequent execute: the
        # per-range "existing snapshot?" lookup inside _upsert_snapshot --
        # none exist yet, so each range inserts a new row.
        session.execute.side_effect = [
            _result_with_scalars_all([listing]),
            *[_result_with_scalars_first(None) for _ in worker.CANONICAL_RANGE_DAYS],
        ]

        with patch.object(
            worker, "_average_response_time_for_listing", AsyncMock(return_value=12.5)
        ):
            written = await worker.refresh_listing_response_times(session)

        assert written == len(worker.CANONICAL_RANGE_DAYS)
        assert session.add.call_count == len(worker.CANONICAL_RANGE_DAYS)
        for call in session.add.call_args_list:
            row = call.args[0]
            assert row.listing_id == "listing-1"
            assert row.average_response_time_minutes == 12.5
            assert row.view_count == 10
            assert row.inquiry_count == 3
        session.commit.assert_awaited_once()

    @pytest.mark.asyncio
    async def test_skips_listings_with_no_inquiries(self) -> None:
        # The real query filters `Listing.inquiry_count > 0` -- simulated
        # here by the mocked select simply returning no rows, standing in
        # for "no listing matched that filter".
        session = AsyncMock()
        session.execute.return_value = _result_with_scalars_all([])

        written = await worker.refresh_listing_response_times(session)

        assert written == 0
        session.add.assert_not_called()
        session.commit.assert_not_called()

    @pytest.mark.asyncio
    async def test_updates_existing_snapshot_rather_than_duplicating(self) -> None:
        listing = _make_listing(id="listing-3", view_count=1, inquiry_count=1)
        session = AsyncMock()

        # First sweep: no existing snapshot -- a new ListingAnalytics row is
        # constructed and passed to session.add.
        session.execute.side_effect = [
            _result_with_scalars_all([listing]),
            _result_with_scalars_first(None),
        ]
        with patch.object(
            worker, "_average_response_time_for_listing", AsyncMock(return_value=5.0)
        ):
            await worker.refresh_listing_response_times(session, range_days_options=(7,))

        inserted_row = session.add.call_args.args[0]
        assert inserted_row.average_response_time_minutes == 5.0

        # Second sweep: the lookup now returns that same row back (as if it
        # had been persisted) -- the worker must mutate it in place rather
        # than insert a second row for the same (listing, range) pair.
        session.execute.side_effect = [
            _result_with_scalars_all([listing]),
            _result_with_scalars_first(inserted_row),
        ]
        with patch.object(
            worker, "_average_response_time_for_listing", AsyncMock(return_value=9.0)
        ):
            await worker.refresh_listing_response_times(session, range_days_options=(7,))

        assert inserted_row.average_response_time_minutes == 9.0
