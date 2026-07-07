"""Transactional email sending -- thin wrapper intended to sit in front of
Amazon SES (see architecture.md / AGENTS.md tech stack table). FEAT-024:
Transactional Email Notifications (Onboarding, Payments, Verification).

Currently a no-op that logs the would-be send -- `aws_ses_sender_email` in
app/core/config.py is still `REPLACE_ME`, so no real SES call is wired up.
Every external dependency call must use a bounded timeout + circuit
breaker and degrade gracefully (AGENTS.md Behavior Rules) -- once SES is
wired here, that wrapping happens in `_send_via_ses`, not at call sites.
"""

from __future__ import annotations

import logging
from typing import Any

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
}


async def send_transactional_email(to: str, template: str, context: dict[str, Any]) -> None:
    """Send a templated transactional email to a known, already-resolved
    address. Low-level primitive -- most call sites should use
    `notify_user` instead, which resolves a User's address and respects
    their notification preferences; this function is for the few cases
    that must bypass that (see `notify_user`'s own docstring), plus
    `notify_user`'s own implementation.

    TODO(payments): replace this log-only stub with a real call to Amazon
    SES (boto3 `ses.send_templated_email` / `send_email`), sourcing the
    verified sender address from `settings.aws_ses_sender_email` once that
    value is populated from Secrets Manager (currently REPLACE_ME). Wrap
    the boto3 call with a bounded timeout + circuit breaker per AGENTS.md
    Behavior Rules, and never let an email failure block/roll back the
    triggering payment or booking transaction -- log and continue.
    """
    if settings.aws_ses_sender_email == "REPLACE_ME":
        logger.info(
            "email_service: no-op send (SES sender not configured) to=%s template=%s context=%s",
            to,
            template,
            context,
        )
        return

    # TODO(payments): real SES integration goes here.
    logger.info("email_service: sending to=%s template=%s context=%s", to, template, context)


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
