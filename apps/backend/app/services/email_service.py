"""Transactional email sending -- thin wrapper intended to sit in front of
Amazon SES (see architecture.md / AGENTS.md tech stack table).

NOTE FOR MERGE: this file is created by the Payments/Booking subagent
(FEAT-032/013/014/027/024) because it did not yet exist. The Auth subagent
may also need it (welcome/verification emails) -- if both subagents created
a version, reconcile at merge time; this implementation is intentionally
generic (template name + context dict) so it should work for both use
cases without modification.

Currently a no-op that logs the would-be send -- `aws_ses_sender_email` in
app/core/config.py is still `REPLACE_ME`, so no real SES call is wired up.
Every external dependency call must use a bounded timeout + circuit
breaker and degrade gracefully (AGENTS.md Behavior Rules) -- once SES is
wired here, that wrapping happens in `_send_via_ses`, not at call sites.
"""

from __future__ import annotations

import logging
from typing import Any

from app.core.config import get_settings

logger = logging.getLogger("app.services.email_service")

settings = get_settings()

# Template names used by this slice; Auth subagent will likely add its own
# (e.g. "welcome", "verify_email", "password_reset") to this same enum-ish
# set of strings.
BOOKING_HOLD_CONFIRMED = "booking_hold_confirmed"
BOOKING_HOLD_EXPIRED = "booking_hold_expired"
PAYMENT_SUCCEEDED = "payment_succeeded"
PAYMENT_FAILED = "payment_failed"


async def send_transactional_email(to: str, template: str, context: dict[str, Any]) -> None:
    """Send a templated transactional email.

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
