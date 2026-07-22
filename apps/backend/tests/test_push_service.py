"""Tests for app/services/push_service.py -- FEAT-022 (Push Notifications).

Covers notify_user's user-lookup, no-registered-devices skip, and
per-category preference gating (mirrors test_email_service.py's coverage
of email_service.notify_user exactly, since push_service was deliberately
structured to match it) -- plus push-specific coverage: the real FCM send
path (mocked at the SDK boundary, `firebase_admin.messaging.send_each_for_multicast`)
and stale-token pruning on UnregisteredError.
"""

from __future__ import annotations

from unittest.mock import AsyncMock, patch

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.push_token import PushToken
from app.models.user import DEFAULT_PUSH_NOTIFICATION_PREFERENCES, User
from app.services import push_service


async def _make_user(session: AsyncSession, **overrides) -> User:
    defaults = {"full_name": "Test User", "email": "user@example.com", "role": "guest"}
    defaults.update(overrides)
    user = User(**defaults)
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return user


async def _register_token(session: AsyncSession, user_id: str, token: str = "tok-1") -> PushToken:
    push_token = PushToken(user_id=user_id, token=token, platform="android")
    session.add(push_token)
    await session.commit()
    return push_token


def test_new_user_defaults_to_all_categories_enabled() -> None:
    user = User(full_name="Test", email="a@b.com", role="guest")
    assert user.push_notification_preferences == DEFAULT_PUSH_NOTIFICATION_PREFERENCES


async def test_notify_user_sends_when_category_enabled_and_device_registered(
    session: AsyncSession,
) -> None:
    user = await _make_user(session)
    await _register_token(session, user.id)
    mock_send = AsyncMock()
    with patch.object(push_service, "_send_via_fcm", mock_send):
        await push_service.notify_user(
            session,
            user_id=user.id,
            template=push_service.BOOKING_HOLD_CONFIRMED,
            context={"transaction_id": "t1"},
        )

    mock_send.assert_awaited_once_with(
        session, ["tok-1"], push_service.BOOKING_HOLD_CONFIRMED, {"transaction_id": "t1"}
    )


async def test_notify_user_skips_when_category_disabled(session: AsyncSession) -> None:
    user = await _make_user(
        session,
        push_notification_preferences={"listings": True, "chat": True, "payments": False},
    )
    await _register_token(session, user.id)
    mock_send = AsyncMock()
    with patch.object(push_service, "_send_via_fcm", mock_send):
        await push_service.notify_user(
            session, user_id=user.id, template=push_service.PAYMENT_SUCCEEDED, context={}
        )

    mock_send.assert_not_awaited()


async def test_notify_user_skips_when_no_registered_devices(session: AsyncSession) -> None:
    user = await _make_user(session)
    mock_send = AsyncMock()
    with patch.object(push_service, "_send_via_fcm", mock_send):
        await push_service.notify_user(
            session, user_id=user.id, template=push_service.PAYMENT_SUCCEEDED, context={}
        )

    mock_send.assert_not_awaited()


async def test_notify_user_skips_silently_for_unknown_user_id(session: AsyncSession) -> None:
    mock_send = AsyncMock()
    with patch.object(push_service, "_send_via_fcm", mock_send):
        # Must not raise -- a notification is never allowed to fail the
        # triggering business transaction (AGENTS.md Error Handling).
        await push_service.notify_user(
            session, user_id="does-not-exist", template=push_service.PAYMENT_SUCCEEDED, context={}
        )

    mock_send.assert_not_awaited()


async def test_notify_user_defaults_missing_category_key_to_enabled(session: AsyncSession) -> None:
    """A user record with a partial preferences dict must not be silently
    opted out of a category missing from it."""
    user = await _make_user(session, push_notification_preferences={})
    await _register_token(session, user.id)
    mock_send = AsyncMock()
    with patch.object(push_service, "_send_via_fcm", mock_send):
        await push_service.notify_user(
            session, user_id=user.id, template=push_service.PAYMENT_SUCCEEDED, context={}
        )

    mock_send.assert_awaited_once()


def test_every_gated_template_has_a_category() -> None:
    for template in (
        push_service.NEW_CHAT_MESSAGE,
        push_service.BOOKING_HOLD_CONFIRMED,
        push_service.BOOKING_HOLD_EXPIRED,
        push_service.PAYMENT_SUCCEEDED,
        push_service.PAYMENT_FAILED,
        push_service.LISTING_STATUS_CHANGED,
    ):
        assert template in push_service.CATEGORY_BY_TEMPLATE
        assert push_service.CATEGORY_BY_TEMPLATE[template] in DEFAULT_PUSH_NOTIFICATION_PREFERENCES


class _FakeSendResponse:
    def __init__(self, success: bool, exception=None) -> None:
        self.success = success
        self.exception = exception


class _FakeBatchResponse:
    def __init__(self, responses: list[_FakeSendResponse]) -> None:
        self.responses = responses
        self.success_count = sum(1 for r in responses if r.success)
        self.failure_count = sum(1 for r in responses if not r.success)


async def test_send_via_fcm_success_does_not_prune_any_tokens(session: AsyncSession) -> None:
    user = await _make_user(session)
    await _register_token(session, user.id, token="good-token")

    fake_response = _FakeBatchResponse([_FakeSendResponse(success=True)])
    with (
        patch(
            "app.services.push_service._send_multicast_sync",
            return_value=fake_response,
        ),
        patch("app.services.chat_service._get_firebase_app", return_value=object()),
    ):
        await push_service._send_via_fcm(
            session, ["good-token"], push_service.PAYMENT_SUCCEEDED, {}
        )

    result = await session.execute(select(PushToken).where(PushToken.user_id == user.id))
    assert result.scalar_one_or_none() is not None  # token survives


async def test_send_via_fcm_prunes_unregistered_tokens(session: AsyncSession) -> None:
    from firebase_admin.messaging import UnregisteredError

    user = await _make_user(session)
    await _register_token(session, user.id, token="dead-token")

    fake_error = UnregisteredError("token no longer valid")
    fake_response = _FakeBatchResponse([_FakeSendResponse(success=False, exception=fake_error)])
    with (
        patch(
            "app.services.push_service._send_multicast_sync",
            return_value=fake_response,
        ),
        patch("app.services.chat_service._get_firebase_app", return_value=object()),
    ):
        await push_service._send_via_fcm(
            session, ["dead-token"], push_service.PAYMENT_SUCCEEDED, {}
        )

    result = await session.execute(select(PushToken).where(PushToken.token == "dead-token"))
    assert result.scalar_one_or_none() is None  # pruned


async def test_send_via_fcm_skips_gracefully_when_firebase_unconfigured(
    session: AsyncSession,
) -> None:
    from app.services.chat_service import ChatServiceUnavailableError

    with patch(
        "app.services.push_service._send_multicast_sync",
        side_effect=ChatServiceUnavailableError("not configured"),
    ):
        # Must not raise.
        await push_service._send_via_fcm(session, ["tok"], push_service.PAYMENT_SUCCEEDED, {})
