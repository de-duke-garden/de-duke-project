"""Tests for app/services/analytics_service.py -- FEAT-028 (Product
Analytics Instrumentation). The actual "send" is always a no-op/log stub
(settings.analytics_write_key defaults to REPLACE_ME), so these assert on
track_event's contract -- never raising, and logging what it would have
sent -- not against a real event being delivered to a third-party platform.
"""

from __future__ import annotations

import logging

import pytest

from app.services import analytics_service


async def test_track_event_never_raises_when_unconfigured() -> None:
    # No exception, regardless of properties shape.
    await analytics_service.track_event(
        event_name=analytics_service.SEARCH_PERFORMED,
        user_id="user-1",
        properties={"listing_type": "commercial"},
    )


async def test_track_event_works_with_no_user_id() -> None:
    """Unauthenticated actions (e.g. an anonymous search) are still
    tracked, just not attributable to a user -- FEAT-028 AC."""
    await analytics_service.track_event(
        event_name=analytics_service.SEARCH_PERFORMED, user_id=None, properties=None
    )


async def test_track_event_logs_when_unconfigured(caplog: pytest.LogCaptureFixture) -> None:
    with caplog.at_level(logging.INFO, logger="app.services.analytics_service"):
        await analytics_service.track_event(
            event_name=analytics_service.LISTING_VIEWED,
            user_id="user-1",
            properties={"listing_id": "listing-1"},
        )
    assert any("no-op track" in record.message for record in caplog.records)
    assert any("listing_viewed" in record.message for record in caplog.records)


async def test_all_five_required_funnel_events_are_defined() -> None:
    """FEAT-028 AC: search, listing view, chat start, booking start, and
    payment completion are each tracked as distinct events."""
    assert analytics_service.SEARCH_PERFORMED == "search_performed"
    assert analytics_service.LISTING_VIEWED == "listing_viewed"
    assert analytics_service.CHAT_STARTED == "chat_started"
    assert analytics_service.BOOKING_INITIATED == "booking_initiated"
    assert analytics_service.PAYMENT_COMPLETED == "payment_completed"
    # All five must be distinct event names.
    names = {
        analytics_service.SEARCH_PERFORMED,
        analytics_service.LISTING_VIEWED,
        analytics_service.CHAT_STARTED,
        analytics_service.BOOKING_INITIATED,
        analytics_service.PAYMENT_COMPLETED,
    }
    assert len(names) == 5
