"""Tests for app/services/email_service.py -- FEAT-024 (Transactional
Email Notifications). Covers notify_user's user-lookup, missing-email
skip, and per-category preference gating -- the actual send is always a
no-op stub (settings.zeptomail_api_key defaults to REPLACE_ME), so
these assert against send_transactional_email being called or not, not
against a real email being delivered.
"""

from __future__ import annotations

from unittest.mock import AsyncMock

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import DEFAULT_EMAIL_NOTIFICATION_PREFERENCES, User
from app.services import email_service


async def _make_user(session: AsyncSession, **overrides) -> User:
    defaults = {
        "full_name": "Test User",
        "email": "user@example.com",
        "role": "guest",
    }
    defaults.update(overrides)
    user = User(**defaults)
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return user


async def test_new_user_defaults_to_all_categories_enabled(session: AsyncSession) -> None:
    user = await _make_user(session)
    assert user.email_notification_preferences == DEFAULT_EMAIL_NOTIFICATION_PREFERENCES


async def test_notify_user_sends_when_category_enabled(
    session: AsyncSession, monkeypatch: pytest.MonkeyPatch
) -> None:
    user = await _make_user(session)
    mock_send = AsyncMock()
    monkeypatch.setattr(email_service, "send_transactional_email", mock_send)

    await email_service.notify_user(
        session, user_id=user.id, template=email_service.WELCOME, context={"full_name": "Test"}
    )

    mock_send.assert_awaited_once_with(
        to="user@example.com", template=email_service.WELCOME, context={"full_name": "Test"}
    )


async def test_notify_user_skips_when_category_disabled(
    session: AsyncSession, monkeypatch: pytest.MonkeyPatch
) -> None:
    user = await _make_user(
        session,
        email_notification_preferences={"account": False, "verification": True, "payments": True},
    )
    mock_send = AsyncMock()
    monkeypatch.setattr(email_service, "send_transactional_email", mock_send)

    await email_service.notify_user(
        session, user_id=user.id, template=email_service.WELCOME, context={}
    )

    mock_send.assert_not_awaited()


async def test_notify_user_skips_when_no_email_on_file(
    session: AsyncSession, monkeypatch: pytest.MonkeyPatch
) -> None:
    user = await _make_user(session, email=None, phone_number="+2348012340000")
    mock_send = AsyncMock()
    monkeypatch.setattr(email_service, "send_transactional_email", mock_send)

    await email_service.notify_user(
        session, user_id=user.id, template=email_service.WELCOME, context={}
    )

    mock_send.assert_not_awaited()


async def test_notify_user_skips_silently_for_unknown_user_id(
    monkeypatch: pytest.MonkeyPatch, session: AsyncSession
) -> None:
    mock_send = AsyncMock()
    monkeypatch.setattr(email_service, "send_transactional_email", mock_send)

    # Must not raise -- a notification is never allowed to fail the
    # triggering business transaction (AGENTS.md Error Handling).
    await email_service.notify_user(
        session, user_id="does-not-exist", template=email_service.WELCOME, context={}
    )

    mock_send.assert_not_awaited()


async def test_notify_user_defaults_missing_category_key_to_enabled(
    session: AsyncSession, monkeypatch: pytest.MonkeyPatch
) -> None:
    """A user record created before a new category existed (or with a
    partial preferences dict) must not be silently opted out of it."""
    user = await _make_user(session, email_notification_preferences={})
    mock_send = AsyncMock()
    monkeypatch.setattr(email_service, "send_transactional_email", mock_send)

    await email_service.notify_user(
        session, user_id=user.id, template=email_service.PAYMENT_SUCCEEDED, context={}
    )

    mock_send.assert_awaited_once()


async def test_send_noops_when_zeptomail_not_configured(monkeypatch: pytest.MonkeyPatch) -> None:
    """With the ZeptoMail API key at its REPLACE_ME default, a send is a
    logged no-op -- never a raised error that could fail a business
    transaction."""
    monkeypatch.setattr(email_service.settings, "zeptomail_api_key", "REPLACE_ME")
    await email_service.send_transactional_email(
        to="user@example.com", template=email_service.WELCOME, context={}
    )
    # No exception raised is the assertion; the no-op path just logs.


def test_render_welcome_template_uses_branded_shell() -> None:
    """The welcome template renders through the shared base.html shell with
    the De-Duke logo and brand-styled markup -- not a bare plain-text
    fallback."""
    import json

    html = email_service._render_template(email_service.WELCOME, json.dumps({"full_name": "Amaka"}))
    assert "Welcome to De-Duke" in html
    assert "de-duke.com/logo.png" in html
    assert "Amaka" in html
    assert html.startswith("<!DOCTYPE html>")


def test_render_payment_template_formats_naira() -> None:
    import json

    html = email_service._render_template(
        email_service.PAYMENT_SUCCEEDED,
        json.dumps({"transaction_id": "txn-1", "gross_amount": 50000.0}),
    )
    assert "50,000.00" in html


def test_render_missing_template_falls_back_without_raising() -> None:
    import json

    html = email_service._render_template("does_not_exist", json.dumps({}))
    assert "does_not_exist" in html


def test_every_gated_template_has_a_category() -> None:
    """staff_invite is the sole deliberate exception (see
    CATEGORY_BY_TEMPLATE's own comment) -- every other template must map
    to a real category so notify_user's preference check actually applies."""
    gated_templates = {
        email_service.WELCOME,
        email_service.PASSWORD_RESET,
        email_service.ACCOUNT_DELETION_CONFIRMED,
        email_service.HOST_VERIFICATION_APPROVED,
        email_service.HOST_VERIFICATION_REJECTED,
        email_service.BOOKING_HOLD_CONFIRMED,
        email_service.BOOKING_HOLD_EXPIRED,
        email_service.PAYMENT_SUCCEEDED,
        email_service.PAYMENT_FAILED,
        email_service.HOST_PAYOUT_SUMMARY,
    }
    for template in gated_templates:
        assert template in email_service.CATEGORY_BY_TEMPLATE
        assert (
            email_service.CATEGORY_BY_TEMPLATE[template] in DEFAULT_EMAIL_NOTIFICATION_PREFERENCES
        )
    assert email_service.STAFF_INVITE not in email_service.CATEGORY_BY_TEMPLATE
