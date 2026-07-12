"""Product analytics event tracking -- FEAT-028 (Product Analytics
Instrumentation). Thin wrapper intended to sit in front of a real Product
Analytics Platform (Amplitude/Mixpanel or a self-hosted equivalent, per
architecture.md's Component: Product Analytics Pipeline / External
Dependencies table) that ingests these events and materializes them into
the aggregate store FEAT-034/FEAT-035's dashboards read from.

Currently a no-op that logs the would-be event -- `analytics_write_key` in
app/core/config.py is still REPLACE_ME, so no real HTTP call is wired up.
Mirrors app/services/email_service.py's exact shape and rationale: never
raise, never block or degrade the underlying user action (FEAT-028
acceptance criterion), log-and-continue until real credentials exist.
"""

from __future__ import annotations

import logging
from typing import Any

from app.core.config import get_settings

logger = logging.getLogger("app.services.analytics_service")

settings = get_settings()

# Event names -- the five funnel events FEAT-028's acceptance criteria
# require to be "tracked as distinct events", plus the funnel steps
# FEAT-035's business dashboard needs (search -> view -> inquiry ->
# booking) and the FEAT-034 operational events (moderation/verification/
# dispute/support activity) architecture.md's Product Analytics Pipeline
# component says this pipeline captures.
SEARCH_PERFORMED = "search_performed"
LISTING_VIEWED = "listing_viewed"
CHAT_STARTED = "chat_started"
BOOKING_INITIATED = "booking_initiated"
PAYMENT_COMPLETED = "payment_completed"


def _is_configured() -> bool:
    return settings.analytics_write_key != "REPLACE_ME"


async def track_event(
    *,
    event_name: str,
    user_id: str | None,
    properties: dict[str, Any] | None = None,
) -> None:
    """Records a single product analytics event.

    `user_id` is None for unauthenticated actions (e.g. an anonymous
    search) -- events are still tracked, just not attributable to a user
    (FEAT-028 AC: "attributable to a user where authenticated").

    `properties` must never contain sensitive data -- no government ID/
    document numbers, no raw card/payment details, no full addresses
    beyond what's already public on a listing (FEAT-028 AC). Callers pass
    only IDs (listing_id, transaction_id, conversation_id) and small
    categorical values (transaction_type, listing_type, search filters) --
    never anything from HostAccount's document fields or Transaction's
    payment_processor_reference/raw gateway payload.

    Never raises -- a tracking failure (network error, pipeline downtime,
    or simply being unconfigured) must never block or degrade the
    triggering user action, exactly like email_service.send_transactional_email
    and push_service's own external-call error handling.
    """
    if not _is_configured():
        logger.info(
            "analytics_service: no-op track (analytics_write_key not configured) "
            "event=%s user_id=%s properties=%s",
            event_name,
            user_id,
            properties or {},
        )
        return

    try:
        # TODO(analytics): real HTTP call to the configured Product
        # Analytics Platform's track/event-ingestion API goes here (e.g.
        # Amplitude's HTTP API v2, Mixpanel's /track, or a self-hosted
        # equivalent's ingestion endpoint), using settings.analytics_write_key.
        # Bounded timeout, matching payment_service.py/push_service.py's own
        # external-call pattern (AGENTS.md Behavior Rules) -- not yet
        # implementable without a real, configured platform to call.
        logger.info(
            "analytics_service: sending event=%s user_id=%s properties=%s",
            event_name,
            user_id,
            properties or {},
        )
    except Exception:  # noqa: BLE001 -- must never propagate to the caller
        logger.exception(
            "analytics_service: failed to track event=%s user_id=%s", event_name, user_id
        )
