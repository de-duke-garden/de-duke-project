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
from functools import cache
from pathlib import Path
from typing import Any

import httpx
from jinja2 import Environment, FileSystemLoader, select_autoescape
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings

logger = logging.getLogger("app.services.email_service")

settings = get_settings()

# Jinja2 environment over the email_templates/ directory. Each template
# extends base.html (shared branded shell -- logo from de-duke.com, tokens
# from branding.md). autoescape is on for HTML safety since template
# contexts can contain user-provided strings (listing titles, names).
_TEMPLATES_DIR = Path(__file__).parent / "email_templates"
_env = Environment(
    loader=FileSystemLoader(_TEMPLATES_DIR),
    autoescape=select_autoescape(["html", "xml"]),
    enable_async=False,
)


@cache
def _render_template(template: str, context_json: str) -> str:
    """Renders `template` + `context` to HTML via Jinja2, cached per
    template+context (serialized). Falls back to a plain-text rendering if
    the template file is missing (never raises -- an email failure must never
    block the triggering transaction)."""
    try:
        import json

        context = json.loads(context_json)
        tpl = _env.get_template(f"{template}.html")
        return tpl.render(**context)
    except Exception:
        logger.exception("email_service: template render failed template=%s", template)
        return f"{template} email. Context: {context_json}"


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
    """Renders `template` + `context` into branded HTML (Jinja2, base.html
    shell) plus a plain-text fallback, then POSTs both to ZeptoMail's
    SendMail API. ZeptoMail requires the sender to be a verified address on
    the `send.de-duke.com` subdomain; the mail_from uses the verified bounce
    (return-path) domain."""
    import json

    context_json = json.dumps(context, default=str)
    html_body = _render_template(template, context_json)
    text_body = f"{template.replace('_', ' ').title()} email\n\nContext:\n{context}"

    payload = {
        "from": {"address": settings.transactional_sender_email},
        "to": [{"email_address": {"address": to}}],
        "subject": _render_subject(template, context),
        "htmlbody": html_body,
        "textbody": text_body,
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


_SUBJECT_BY_TEMPLATE: dict[str, str] = {
    "welcome": "Welcome to De-Duke",
    "password_reset": "Reset your password",
    "account_deletion_confirmed": "Your De-Duke account has been deleted",
    "host_verification_approved": "You're verified on De-Duke",
    "host_verification_rejected": "Verification update",
    "booking_hold_confirmed": "Your booking is on hold",
    "booking_hold_expired": "Your booking hold has expired",
    "payment_succeeded": "Payment received",
    "payment_failed": "Payment unsuccessful",
    "host_payout_summary": "Your payout summary",
    "staff_invite": "You've been invited to De-Duke",
    "dispute_resolved": "Your dispute has been resolved",
    "escrow_funds_released": "Your funds have been released",
    "withdrawal_paid": "Withdrawal completed",
    "withdrawal_failed": "Withdrawal unsuccessful",
}


def _render_subject(template: str, context: dict[str, Any]) -> str:
    """Human-readable subject per template (fallback to a derived title)."""
    return _SUBJECT_BY_TEMPLATE.get(template, template.replace("_", " ").title())


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
