"""Tests for app/services/moderation_service.py -- FEAT-025 (Admin
Moderation Queue) decision logic, plus its FEAT-022 push notification
side-effect on apply_moderation_decision.

`Listing` has a PostGIS Geography column (location_point), which the
SQLite test harness excludes from table creation (see conftest.py's
_sqlite_safe_tables) -- so Listing/HostAccount rows here are plain
SimpleNamespace stand-ins with a mocked session, the same pattern
test_chat.py already uses for the same reason (ChatConversation's
listing-resolution tests).
"""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.services import moderation_service


def _make_listing(**overrides) -> SimpleNamespace:
    defaults = {
        "id": "listing-1",
        "host_account_id": "host-account-1",
        "status": "under_review",
        "status_reason": None,
    }
    defaults.update(overrides)
    return SimpleNamespace(**defaults)


def _make_session_with_host_account(host_account) -> MagicMock:
    session = MagicMock()

    async def fake_get(model, pk):  # noqa: ANN001, ARG001
        return host_account

    session.get = fake_get
    session.add = MagicMock()
    session.commit = AsyncMock()
    session.refresh = AsyncMock()
    return session


@pytest.mark.asyncio
async def test_approve_sets_active_status_and_clears_reason() -> None:
    listing = _make_listing(status="under_review", status_reason=None)
    host_account = SimpleNamespace(user_id="host-user-1")
    session = _make_session_with_host_account(host_account)

    with patch.object(moderation_service.push_service, "notify_user", AsyncMock()) as mock_notify:
        result = await moderation_service.apply_moderation_decision(
            session, listing=listing, action="approve", reason=""
        )

    assert result.status == "active"
    assert result.status_reason is None
    mock_notify.assert_awaited_once_with(
        session,
        user_id="host-user-1",
        template=moderation_service.push_service.LISTING_STATUS_CHANGED,
        context={"listing_id": "listing-1", "action": "approve", "reason": ""},
    )


@pytest.mark.asyncio
async def test_ban_sets_banned_status_and_reason() -> None:
    listing = _make_listing(status="under_review", status_reason=None)
    host_account = SimpleNamespace(user_id="host-user-1")
    session = _make_session_with_host_account(host_account)

    with patch.object(moderation_service.push_service, "notify_user", AsyncMock()) as mock_notify:
        result = await moderation_service.apply_moderation_decision(
            session, listing=listing, action="ban", reason="Fraudulent listing"
        )

    assert result.status == "banned"
    assert result.status_reason == "Fraudulent listing"
    mock_notify.assert_awaited_once_with(
        session,
        user_id="host-user-1",
        template=moderation_service.push_service.LISTING_STATUS_CHANGED,
        context={"listing_id": "listing-1", "action": "ban", "reason": "Fraudulent listing"},
    )


@pytest.mark.asyncio
async def test_invalid_action_raises_before_any_notification() -> None:
    listing = _make_listing()
    session = _make_session_with_host_account(SimpleNamespace(user_id="host-user-1"))

    with patch.object(moderation_service.push_service, "notify_user", AsyncMock()) as mock_notify:
        with pytest.raises(ValueError):
            await moderation_service.apply_moderation_decision(
                session, listing=listing, action="not-a-real-action", reason=""
            )

    mock_notify.assert_not_awaited()


@pytest.mark.asyncio
async def test_notification_skipped_gracefully_when_host_account_missing() -> None:
    """A dangling host_account_id (shouldn't happen given the FK, but
    apply_moderation_decision must not crash the moderation decision
    itself over a notification-resolution failure)."""
    listing = _make_listing()
    session = _make_session_with_host_account(None)

    with patch.object(moderation_service.push_service, "notify_user", AsyncMock()) as mock_notify:
        result = await moderation_service.apply_moderation_decision(
            session, listing=listing, action="approve", reason=""
        )

    assert result.status == "active"
    mock_notify.assert_not_awaited()
