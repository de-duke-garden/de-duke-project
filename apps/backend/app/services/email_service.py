"""Transactional email sending -- thin wrapper in front of ZeptoMail
(see architecture.md / AGENTS.md tech stack table). FEAT-024:
Transactional Email Notifications (Onboarding, Payments, Verification).

ZeptoMail is the transactional provider for noreply@de-duke.com; the
mailboxes (info/hello/legal@) live in Zoho Mail. Every external dependency
call must use a bounded timeout + circuit breaker and degrade gracefully
(AGENTS.md Behavior Rules) -- an email failure must never block or roll
back the triggering business transaction, so failures are logged and
swallowed here, never raised to callers.
"""

from __future__ import annotations

import logging
import time
from typing import Any

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings

logger = logging.getLogger("app.services.email_service")

settings = get_settings()

# Template names. Each maps to a category below for per-user preference
# gating (User.email_notification_preferences, FEAT-024 AC) -- except
# STAFF_INVITE, which is deliberately ungated (see notify_user).
WELCOME = "welcome"
PASSWORD_RESET = "password_reset"
ACCOUNT_DELETION_CONFIRMED = "account_deletion_confirmed"
HOST_VERIFICATION_APPROVED = "host_verification_approved"
HOST_VERIFICATION_REJECTED = "host_verification_rejected"
BOOKING_HOLD_CONFIRMED = "booking_hold_confirmed"
BOOKING_HOLD_EXPIRED = "booking_hold_expired"
PAYMENT_SUCCEEDED = "payment_succeeded"
PAYMENT_FAILED = "payment_failed"
HOST_PAYOUT_SUMMARY = "host_payout_summary"
STAFF_INVITE = "staff_invite"
DISPUTE_RESOLVED = "dispute_resolved"
# FEAT-043/045 (escrow release + wallet withdrawal, schema.md's Escrow
# model). ESCROW_FUNDS_RELEASED replaces HOST_PAYOUT_SUMMARY's old firing
# point (paystack_webhook_handler.py, at raw payment success) -- see that
# module's docstring for why sending a "payout summary" at payment time
# was actively misleading before a De-Duke Admin had released anything.
ESCROW_FUNDS_RELEASED = "escrow_funds_released"
WITHDRAWAL_PAID = "withdrawal_paid"
WITHDRAWAL_FAILED = "withdrawal_failed"

# FEAT-024 AC: "User can manage email notification preferences per
# category in settings, separate from push preferences." Three categories
# cover every template above; STAFF_INVITE has no entry -- it is not a
# discretionary notification (it's how a brand-new internal account gets
# access at all), so it is never gated by user preference.
CATEGORY_BY_TEMPLATE: dict[str, str] = {
    WELCOME: "account",
    PASSWORD_RESET: "account",
    ACCOUNT_DELETION_CONFIRMED: "account",
    HOST_VERIFICATION_APPROVED: "verification",
    HOST_VERIFICATION_REJECTED: "verification",
    BOOKING_HOLD_CONFIRMED: "payments",
    BOOKING_HOLD_EXPIRED: "payments",
    PAYMENT_SUCCEEDED: "payments",
    PAYMENT_FAILED: "payments",
    HOST_PAYOUT_SUMMARY: "payments",
    DISPUTE_RESOLVED: "payments",
    ESCROW_FUNDS_RELEASED: "payments",
    WITHDRAWAL_PAID: "payments",
    WITHDRAWAL_FAILED: "payments",
}


class _CircuitBreaker:
    """Simple consecutive-failure breaker (same pattern as
    embedding_service.py) -- opens after `failure_threshold` back-to-back
    failures/timeouts, refuses calls for `cooldown_seconds`, then
    half-opens (lets exactly one call through) to probe recovery."""

    def __init__(self, failure_threshold: int, cooldown_seconds: float) -> None:
        self._failure_threshold = failure_threshold
        self._cooldown_seconds = cooldown_seconds
        self._consecutive_failures = 0
        self._opened_at: float | None = None

    def is_open(self) -> bool:
        if self._opened_at is None:
            return False
        if time.monotonic() - self._opened_at >= self._cooldown_seconds:
            self._opened_at = None
            self._consecutive_failures = 0
            return False
        return True

    def record_success(self) -> None:
        self._consecutive_failures = 0
        self._opened_at = None

    def record_failure(self) -> None:
        self._consecutive_failures += 1
        if self._consecutive_failures >= self._failure_threshold and self._opened_at is None:
            self._opened_at = time.monotonic()


_breaker = _CircuitBreaker(failure_threshold=3, cooldown_seconds=30.0)

_ZEPTOMAIL_API_URL = "https://api.zeptomail.com/v1.1/email"
_SEND_TIMEOUT_SECONDS = 10.0


async def send_transactional_email(to: str, template: str, context: dict[str, Any]) -> None:
    """Send a templated transactional email to a known, already-resolved
    address. Low-level primitive -- most call sites should use
    `notify_user` instead, which resolves a User's address and respects
    their notification preferences; this function is for the few cases
    that must bypass that (see `notify_user`'s own docstring), plus
    `notify_user`'s own implementation.

    Sends via ZeptoMail (bounded timeout + circuit breaker per AGENTS.md
    Behavior Rules). Never lets an email failure block or roll back the
    triggering payment or booking transaction -- failures are logged and
    swallowed, not raised.
    """
    if settings.zeptomail_api_key == "REPLACE_ME":
        logger.info(
            "email_service: no-op send (ZeptoMail API key not configured) to=%s template=%s",
            to,
            template,
        )
        return

    if _breaker.is_open():
        logger.warning(
            "email_service: circuit breaker open, skipping to=%s template=%s", to, template
        )
        return

    try:
        await _send_via_zeptomail(to=to, template=template, context=context)
        _breaker.record_success()
    except Exception:
        # Never let an email failure block the triggering transaction.
        logger.exception("email_service: ZeptoMail send failed to=%s template=%s", to, template)
        _breaker.record_failure()


async def _send_via_zeptomail(to: str, template: str, context: dict[str, Any]) -> None:
    """Renders `template` + `context` into a plain-text/HTML body and POSTs
    to ZeptoMail's SendMail API. ZeptoMail requires the sender to be a
    verified address on the `send.de-duke.com` subdomain, and the
    mail_from address uses the verified bounce (return-path) domain."""
    subject = f"De-Duke: {template.replace('_', ' ').title()}"
    body = f"{template} email\n\nContext:\n{context}"

    payload = {
        "from": {"address": settings.transactional_sender_email},
        "to": [{"email_address": {"address": to}}],
        "subject": subject,
        "textbody": body,
        "track_clicks": False,
        "track_opens": False,
    }

    async with httpx.AsyncClient(timeout=_SEND_TIMEOUT_SECONDS) as client:
        resp = await client.post(
            _ZEPTOMAIL_API_URL,
            headers={
                "Authorization": f"Zoho-enczapikey {settings.zeptomail_api_key}",
                "Content-Type": "application/json",
            },
            json=payload,
        )
        resp.raise_for_status()


async def notify_user(
    session: AsyncSession, *, user_id: str, template: str, context: dict[str, Any]
) -> None:
    """Resolves `user_id` to its current email address and per-category
    preference before sending -- the correct way for almost every call
    site to send a transactional email, since a User's address can change
    and their preferences must be honored (FEAT-024 AC).

    Silently no-ops (logs and returns) rather than raising when the user
    has no email on file (phone-only account) or has disabled this
    template's category -- a notification being skipped must never fail
    or roll back the triggering business transaction (AGENTS.md Error
    Handling / External Service Resilience).

    Not used for:
      - STAFF_INVITE: the invitee's very first access to their account,
        not a discretionary notification -- call send_transactional_email
        directly with their address.
      - FEAT-030 account deletion confirmation: the User row's email is
        already scrubbed to None by the time the confirmation would send
        (that's the whole point of the deletion) -- the caller must
        capture the address before scrubbing and call
        send_transactional_email directly with it.
    """
    # Local import avoids a circular import (app.models.user -> nothing
    # back to this module today, but matches the existing local-import
    # pattern used elsewhere, e.g. verification_service.py, for the same
    # defensive reason).
    from app.models.user import User

    user = await session.get(User, user_id)
    if user is None or not user.email:
        logger.info(
            "notify_user: skipping template=%s user_id=%s (no email on file)", template, user_id
        )
        return

    category = CATEGORY_BY_TEMPLATE.get(template)
    if category is not None:
        preferences = user.email_notification_preferences or {}
        # Missing key defaults to enabled -- see
        # DEFAULT_EMAIL_NOTIFICATION_PREFERENCES's own comment on why.
        if preferences.get(category, True) is False:
            logger.info(
                "notify_user: skipping template=%s user_id=%s (category '%s' disabled)",
                template,
                user_id,
                category,
            )
            return

    await send_transactional_email(to=user.email, template=template, context=context)
