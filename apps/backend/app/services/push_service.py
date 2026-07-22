"""Push notification sending -- FEAT-022 (Push Notifications). Deliberately
structured to mirror app/services/email_service.py's shape (template
constants, CATEGORY_BY_TEMPLATE, a notify_user-equivalent that resolves
preferences before sending) -- see architecture.md's "Notification Service
(Push & Email)" component: "Push and email share the same triggering
events but serve different needs ... Both channels respect user-
configurable per-category preferences."

Real Firebase Cloud Messaging send, via `firebase_admin.messaging` --
reuses chat_service._get_firebase_app()'s already-initialized Firebase
Admin SDK app (one app per process, not a second independent instance).
Like every other external dependency call in this codebase (see
payment_service.py, sms_service.py), this is a bounded-timeout call with
no retry-forever -- there is no circuit-breaker *library* wired up
anywhere in this codebase yet (AGENTS.md's aspiration, not yet a concrete
dependency), so "bounded timeout, fail fast, log and continue" is the
actual, consistent pattern here, matching those two services exactly
rather than introducing a new pattern for this one.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Any

from fastapi import HTTPException, status
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

logger = logging.getLogger("app.services.push_service")

# Template names. Each maps to a category below for per-user preference
# gating (User.push_notification_preferences, FEAT-022 AC).
NEW_CHAT_MESSAGE = "new_chat_message"
BOOKING_HOLD_CONFIRMED = "booking_hold_confirmed"
BOOKING_HOLD_EXPIRED = "booking_hold_expired"
PAYMENT_SUCCEEDED = "payment_succeeded"
PAYMENT_FAILED = "payment_failed"
LISTING_STATUS_CHANGED = "listing_status_changed"
DISPUTE_RESOLVED = "dispute_resolved"
# FEAT-023 (Saved Searches & Listing Alerts) -- additive template, wired
# from app/workers/saved_search_alert_job.py. Category "listings" (below)
# matches LISTING_STATUS_CHANGED's own category for the same reason: this
# is fundamentally a listing-availability notification, just triggered by a
# saved search match rather than a status transition on a listing the user
# owns.
SAVED_SEARCH_MATCH = "saved_search_match"
# FEAT-043/045 (escrow release + wallet withdrawal) -- mirrors
# email_service.py's own ESCROW_FUNDS_RELEASED/WITHDRAWAL_PAID/
# WITHDRAWAL_FAILED additions; see that module's comment for why
# ESCROW_FUNDS_RELEASED replaces the old payment-time payout notification.
ESCROW_FUNDS_RELEASED = "escrow_funds_released"
WITHDRAWAL_PAID = "withdrawal_paid"
WITHDRAWAL_FAILED = "withdrawal_failed"

# FEAT-022 AC: "User can manage notification preferences per category in
# settings" -- push's own category set (listings, chat, payments),
# distinct from email's (account, verification, payments) per FEAT-024's
# "separate from push preferences" AC. See
# app/models/user.py's DEFAULT_PUSH_NOTIFICATION_PREFERENCES.
CATEGORY_BY_TEMPLATE: dict[str, str] = {
    NEW_CHAT_MESSAGE: "chat",
    BOOKING_HOLD_CONFIRMED: "payments",
    BOOKING_HOLD_EXPIRED: "payments",
    PAYMENT_SUCCEEDED: "payments",
    PAYMENT_FAILED: "payments",
    LISTING_STATUS_CHANGED: "listings",
    # A dispute is always raised against a transaction -- "payments"
    # category, same reasoning as BOOKING_HOLD_*/PAYMENT_* above.
    DISPUTE_RESOLVED: "payments",
    SAVED_SEARCH_MATCH: "listings",
    ESCROW_FUNDS_RELEASED: "payments",
    WITHDRAWAL_PAID: "payments",
    WITHDRAWAL_FAILED: "payments",
}

# Notification copy per template. Deliberately plain string formatting
# (not Jinja, unlike email's eventual templates) -- push notification
# copy is short and has no HTML/rich layout to justify a template engine.
# `context` keys referenced here must exist at every call site -- see
# each notify_user(..., context={...}) call across the codebase (bookings.py,
# hold_expiry_job.py, paystack_webhook_handler.py, chat_service.py).
_COPY_BY_TEMPLATE: dict[str, tuple[str, str]] = {
    NEW_CHAT_MESSAGE: ("New message", "You have a new message on De-Duke."),
    BOOKING_HOLD_CONFIRMED: (
        "Booking held",
        "Your booking is held -- complete payment before it expires.",
    ),
    BOOKING_HOLD_EXPIRED: (
        "Hold expired",
        "Your booking hold expired. The listing may no longer be available.",
    ),
    PAYMENT_SUCCEEDED: ("Payment successful", "Your payment was completed successfully."),
    PAYMENT_FAILED: ("Payment failed", "Your payment didn't go through -- please retry in-app."),
    LISTING_STATUS_CHANGED: ("Listing update", "One of your listings has a status update."),
    DISPUTE_RESOLVED: ("Dispute resolved", "Your dispute has been reviewed and resolved."),
    SAVED_SEARCH_MATCH: (
        "New match for your saved search",
        "A new listing matches one of your saved searches.",
    ),
}

# Bounded timeout, matching payment_service.py/sms_service.py's own
# constants for the same "never let a hung external dependency pile up
# slow requests" reason (AGENTS.md Behavior Rules).
_FCM_TIMEOUT_SECONDS = 10


def _build_notification(template: str) -> Any:
    from firebase_admin import messaging

    title, body = _COPY_BY_TEMPLATE.get(template, ("De-Duke", "You have a new notification."))
    return messaging.Notification(title=title, body=body)


def _send_multicast_sync(tokens: list[str], template: str) -> Any:
    """The actual blocking Firebase Admin SDK call -- run off the event
    loop via asyncio.to_thread in _send_via_fcm, since firebase_admin's
    messaging API is synchronous (same accepted tradeoff
    chat_service.py's Firestore calls already make in this codebase, but
    made explicit here via to_thread since this is a real network call
    with real latency, not a call site worth blocking the loop for).
    """
    from firebase_admin import messaging

    from app.services.chat_service import _get_firebase_app

    message = messaging.MulticastMessage(tokens=tokens, notification=_build_notification(template))
    return messaging.send_each_for_multicast(message, app=_get_firebase_app())


async def _prune_invalid_tokens(session: AsyncSession, invalid_tokens: list[str]) -> None:
    """A send failure for a specific token (unregistered/invalid -- app
    uninstalled, token rotated without a refresh event reaching us) must
    prune that PushToken row, not retry indefinitely against a dead
    device (this function's own docstring requirement, carried over from
    the original TODO)."""
    if not invalid_tokens:
        return
    from app.models.push_token import PushToken

    await session.execute(delete(PushToken).where(PushToken.token.in_(invalid_tokens)))
    await session.commit()


async def _send_via_fcm(
    session: AsyncSession, tokens: list[str], template: str, context: dict[str, Any]
) -> None:
    """Sends a real push via FCM to every token, then prunes any token FCM
    reports as invalid/unregistered. `context` is accepted for parity with
    email_service's equivalent signature and future richer payloads (deep
    links, data-only fields) but isn't used in the notification body today
    -- see _COPY_BY_TEMPLATE's plain, context-free copy.
    """
    from firebase_admin.exceptions import FirebaseError

    from app.services.chat_service import ChatServiceUnavailableError

    try:
        response = await asyncio.wait_for(
            asyncio.to_thread(_send_multicast_sync, tokens, template),
            timeout=_FCM_TIMEOUT_SECONDS,
        )
    except ChatServiceUnavailableError as exc:
        # Reuses chat_service's own "Firebase Admin SDK not configured in
        # this environment" guard rather than duplicating it -- same
        # underlying Firebase app, same REPLACE_ME-credentials check.
        logger.info("push_service: FCM unavailable (%s), skipping send template=%s", exc, template)
        return
    except (TimeoutError, FirebaseError) as exc:
        logger.warning("push_service: FCM send failed template=%s error=%s", template, exc)
        return

    # UnregisteredError is the SDK's own dedicated exception type for a
    # dead token (app uninstalled, token rotated) -- confirmed against the
    # installed firebase-admin version (_messaging_utils.UnregisteredError,
    # a subclass of exceptions.NotFoundError) rather than guessed at via
    # string error codes, which differ across SDK versions.
    from firebase_admin.messaging import UnregisteredError

    invalid_tokens = [
        token
        for token, result in zip(tokens, response.responses, strict=True)
        if not result.success and isinstance(result.exception, UnregisteredError)
    ]
    await _prune_invalid_tokens(session, invalid_tokens)

    if response.failure_count:
        logger.info(
            "push_service: sent template=%s success=%d failure=%d (pruned %d invalid tokens)",
            template,
            response.success_count,
            response.failure_count,
            len(invalid_tokens),
        )


async def notify_user(
    session: AsyncSession, *, user_id: str, template: str, context: dict[str, Any]
) -> None:
    """Resolves `user_id` to its registered device tokens and per-category
    preference before sending -- the correct way for almost every call
    site to send a push notification, mirroring email_service.notify_user
    exactly (see that function's docstring for the shared rationale).

    Silently no-ops when the user has no registered devices or has
    disabled this template's category -- a notification being skipped
    must never fail or roll back the triggering business transaction.
    """
    # Local imports avoid a circular import, same defensive pattern as
    # email_service.notify_user.
    from app.models.push_token import PushToken
    from app.models.user import User

    user = await session.get(User, user_id)
    if user is None:
        logger.info(
            "notify_user: skipping template=%s user_id=%s (no such user)", template, user_id
        )
        return

    category = CATEGORY_BY_TEMPLATE.get(template)
    if category is not None:
        preferences = user.push_notification_preferences or {}
        # Missing key defaults to enabled -- see
        # DEFAULT_PUSH_NOTIFICATION_PREFERENCES's own comment on why.
        if preferences.get(category, True) is False:
            logger.info(
                "notify_user: skipping template=%s user_id=%s (category '%s' disabled)",
                template,
                user_id,
                category,
            )
            return

    result = await session.execute(select(PushToken.token).where(PushToken.user_id == user_id))
    tokens = list(result.scalars().all())
    if not tokens:
        logger.info(
            "notify_user: skipping template=%s user_id=%s (no registered devices)",
            template,
            user_id,
        )
        return

    await _send_via_fcm(session, tokens, template, context)


async def register_token(session: AsyncSession, *, user_id: str, token: str, platform: str) -> None:
    """Upsert by `token` (unique column, see app/models/push_token.py) --
    the same device re-registering (app restart, token refresh delivered
    again) updates its existing row rather than creating a duplicate,
    which would otherwise cause that device to receive every push twice.
    """
    from datetime import UTC, datetime

    from app.models.push_token import PushToken

    result = await session.execute(select(PushToken).where(PushToken.token == token))
    existing = result.scalar_one_or_none()
    if existing is not None:
        existing.user_id = (
            user_id  # re-registering under a different account (e.g. account switch) reassigns it
        )
        existing.platform = platform
        existing.updated_at = datetime.now(UTC)
        session.add(existing)
    else:
        session.add(PushToken(user_id=user_id, token=token, platform=platform))
    await session.commit()


async def get_notification_preferences(session: AsyncSession, *, user_id: str) -> dict[str, bool]:
    from app.models.user import User

    user = await session.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Account not found.")
    return dict(user.push_notification_preferences or {})


async def update_notification_preferences(
    session: AsyncSession, *, user_id: str, updates: dict[str, bool]
) -> dict[str, bool]:
    from datetime import UTC, datetime

    from app.models.user import User

    user = await session.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Account not found.")

    preferences = dict(user.push_notification_preferences or {})
    preferences.update(updates)
    user.push_notification_preferences = preferences
    user.updated_at = datetime.now(UTC)
    session.add(user)
    await session.commit()
    return preferences
