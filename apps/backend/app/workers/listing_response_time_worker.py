"""FEAT-019 -- Lead Analytics per Listing: average response time worker.

`app/services/agency_service.py::get_listing_analytics` has, since its
original implementation, read `ListingAnalytics.average_response_time_minutes`
from whatever snapshot row already exists for the requested (listing,
range_start, range_end) tuple and otherwise returned `None` -- documented
there as a gap because "no background worker in this codebase yet
materializes into ListingAnalytics.average_response_time_minutes". This
worker is that missing piece.

It reads first-response gaps directly out of Firestore (ChatConversation +
its `messages` subcollection -- schema.md), which is a new server-side read
touchpoint: `app/services/chat_service.py`'s module docstring previously
said the backend "never reads ChatMessage documents"; that statement now
has this one documented exception (analytics-only, read-only, via the same
`_get_firestore_client()` helper `app/services/push_service.py` already
imports from that module for its own purposes).

Follows the same "pure transition function + no in-repo scheduler" shape as
`app/workers/hold_expiry_job.py` / `app/workers/saved_search_alert_job.py` --
wiring a periodic invocation is an infra/worker-harness concern outside this
slice.
"""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.firestore_models import ChatMessage
from app.models.discovery import ListingAnalytics
from app.models.listing import Listing
from app.services.chat_service import ChatServiceUnavailableError, _get_firestore_client

# FEAT-019 AC: "Metrics are viewable over selectable date ranges (7/30/90
# days)" -- these are the exact three range_days values
# agency_service.get_listing_analytics accepts, so this worker only ever
# needs to materialize snapshots for these three, never an arbitrary range.
CANONICAL_RANGE_DAYS: tuple[int, ...] = (7, 30, 90)

DEFAULT_BATCH_SIZE = 50


def average_first_response_minutes(messages: list[ChatMessage]) -> float | None:
    """Pure function, no Firestore I/O: given a conversation's messages
    (any order), pairs each client message with the next property_management/
    deduke_staff message that follows it chronologically (an in-order,
    each-reply-used-once pairing -- a reply is never double-counted against
    two different client messages), and returns the average gap in minutes.

    Returns None if there is no such client-message-then-reply pair (e.g. an
    empty conversation, or one still awaiting its first reply) -- callers
    surface that as screens.md's documented Empty state, same as the
    pre-existing "no snapshot yet" None case.
    """
    ordered = sorted(messages, key=lambda m: m.sent_at)

    gaps_minutes: list[float] = []
    pending_client_message_at: datetime | None = None
    for message in ordered:
        if message.sender_role == "client":
            # A second client message before any reply supersedes the first
            # as the one we're waiting on a response to.
            pending_client_message_at = message.sent_at
        elif message.sender_role in ("property_management", "deduke_staff"):
            if pending_client_message_at is not None:
                delta = (message.sent_at - pending_client_message_at).total_seconds() / 60
                gaps_minutes.append(delta)
                pending_client_message_at = None
        # System messages (sender_role is None) never count as a reply.

    if not gaps_minutes:
        return None
    return sum(gaps_minutes) / len(gaps_minutes)


def _message_from_doc(doc) -> ChatMessage:  # noqa: ANN001 -- firestore DocumentSnapshot
    data = doc.to_dict() or {}
    return ChatMessage(
        id=doc.id,
        conversation_id=data.get("conversationId", ""),
        sender_id=data.get("senderId"),
        sender_role=data.get("senderRole"),
        message_type=data.get("messageType", "text"),
        body=data.get("body", ""),
        delivery_status=data.get("deliveryStatus", "sent"),
        sent_at=data.get("sentAt"),
    )


async def _average_response_time_for_listing(
    listing_id: str, *, range_start: date, range_end: date
) -> float | None:
    """Reads every conversation created for `listing_id` within
    [range_start, range_end] and averages `average_first_response_minutes`
    across all of them. Returns None (never raises) if Firestore is
    unconfigured/unavailable in this environment -- same graceful-degrade
    contract as the rest of the chat/analytics surface (AGENTS.md's bounded
    timeout + circuit breaker rule), since a materialization worker failing
    must never block the API request path that reads whatever was last
    successfully computed.
    """
    try:
        client = _get_firestore_client()
    except ChatServiceUnavailableError:
        return None

    range_start_dt = datetime.combine(range_start, datetime.min.time(), tzinfo=UTC)
    range_end_dt = datetime.combine(range_end, datetime.max.time(), tzinfo=UTC)

    conversations = list(
        client.collection("conversations")
        .where("listingId", "==", listing_id)
        .where("createdAt", ">=", range_start_dt)
        .where("createdAt", "<=", range_end_dt)
        .stream()
    )

    all_gaps: list[float] = []
    for conversation_doc in conversations:
        message_docs = list(
            conversation_doc.reference.collection("messages").order_by("sentAt").stream()
        )
        messages = [_message_from_doc(doc) for doc in message_docs]
        average = average_first_response_minutes(messages)
        if average is not None:
            all_gaps.append(average)

    if not all_gaps:
        return None
    return sum(all_gaps) / len(all_gaps)


async def _upsert_snapshot(
    session: AsyncSession,
    *,
    listing: Listing,
    range_start: date,
    range_end: date,
    average_response_time_minutes: float | None,
) -> None:
    """Matches app/services/agency_service.py::get_listing_analytics's exact
    lookup keys (listing_id, range_start, range_end) so a snapshot this
    worker writes is the same row that endpoint reads back.

    view_count/inquiry_count are written from the listing's lifetime
    counters -- the same documented approximation get_listing_analytics's
    own fallback path already uses (no time-bucketed view/inquiry event log
    exists yet, per that function's docstring) -- so writing a snapshot row
    here never regresses those two fields versus not having a snapshot at
    all; it only adds the average_response_time_minutes value that was
    otherwise permanently None.
    """
    existing = (
        (
            await session.execute(
                select(ListingAnalytics)
                .where(ListingAnalytics.listing_id == listing.id)
                .where(ListingAnalytics.range_start == range_start)
                .where(ListingAnalytics.range_end == range_end)
                .order_by(ListingAnalytics.id.desc())
            )
        )
        .scalars()
        .first()
    )

    if existing is not None:
        existing.view_count = listing.view_count
        existing.inquiry_count = listing.inquiry_count
        existing.average_response_time_minutes = average_response_time_minutes
        session.add(existing)
    else:
        session.add(
            ListingAnalytics(
                listing_id=listing.id,
                range_start=range_start,
                range_end=range_end,
                view_count=listing.view_count,
                inquiry_count=listing.inquiry_count,
                average_response_time_minutes=average_response_time_minutes,
            )
        )


async def refresh_listing_response_times(
    session: AsyncSession,
    *,
    range_days_options: tuple[int, ...] = CANONICAL_RANGE_DAYS,
    batch_size: int = DEFAULT_BATCH_SIZE,
) -> int:
    """For up to `batch_size` listings that have at least one inquiry
    (inquiry_count > 0 -- a listing nobody has ever messaged about has no
    response time to measure), materializes a ListingAnalytics snapshot for
    each of `range_days_options` with a freshly computed
    average_response_time_minutes. Returns the number of (listing, range)
    snapshots written.
    """
    result = await session.execute(
        select(Listing).where(Listing.inquiry_count > 0).limit(batch_size)
    )
    listings = list(result.scalars().all())
    if not listings:
        return 0

    range_end = date.today()
    written = 0
    for listing in listings:
        for range_days in range_days_options:
            range_start = range_end - timedelta(days=range_days)
            average = await _average_response_time_for_listing(
                listing.id, range_start=range_start, range_end=range_end
            )
            await _upsert_snapshot(
                session,
                listing=listing,
                range_start=range_start,
                range_end=range_end,
                average_response_time_minutes=average,
            )
            written += 1

    await session.commit()
    return written
