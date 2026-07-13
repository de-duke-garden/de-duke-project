"""FEAT-031 -- Listing (re)embedding background job.

(Re)computes `Listing.description_embedding` for any listing whose embedding
is missing or stale (`embedding_updated_at is NULL` or older than the
listing's own `updated_at`), so a newly published or edited listing is
reflected in semantic search results "within a few minutes" (FEAT-031 AC),
without the publish/edit request path itself blocking on an embedding call.

Follows the same pattern as app/workers/hold_expiry_job.py: this module only
exposes the pure, testable transition function. Wiring a periodic/SQS-driven
invocation of it is an infra/worker-harness concern (architecture.md's
Background Task Processor) outside this slice -- no SQS consumer loop exists
anywhere yet in this codebase (paystack_webhook_handler.py and
hold_expiry_job.py are likewise invoked by that not-yet-built harness).
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.listing import Listing
from app.services.embedding_service import embed_text

# Background embedding is not user-facing -- a generous timeout is fine here
# (unlike search_service's short query-time budget); still bounded, per
# AGENTS.md's "every external dependency call uses a bounded timeout" rule,
# so one stuck listing can never hang the whole batch indefinitely.
_EMBEDDING_TIMEOUT_SECONDS = 10.0

DEFAULT_BATCH_SIZE = 50


def _embedding_input_text(listing: Listing) -> str:
    """Builds the text fed to the embedding provider from a listing's
    description/attributes (FEAT-031's description: "semantic similarity
    between the user's query and each listing's description/attributes").
    Title and amenities are included alongside the free-text description so
    e.g. "parking" or "near a school" phrasing in amenities/title also
    contributes to the listing's embedding, not just its description prose.
    """
    parts = [listing.title, listing.description, listing.location_city, listing.location_state]
    parts.extend(listing.amenities or [])
    return " ".join(part for part in parts if part)


async def embed_pending_listings(
    session: AsyncSession, *, batch_size: int = DEFAULT_BATCH_SIZE
) -> int:
    """Finds up to `batch_size` active listings needing a fresh embedding,
    computes it, and commits. Returns the number of listings processed
    (embedded or left unchanged because the embedding call degraded --
    those are simply retried on the worker's next cycle, per
    embed_text's documented "return None on failure" contract).
    """
    result = await session.execute(
        select(Listing)
        .where(Listing.status == "active")
        .where(
            or_(
                Listing.embedding_updated_at.is_(None),
                Listing.embedding_updated_at < Listing.updated_at,
            )
        )
        .limit(batch_size)
    )
    listings = list(result.scalars().all())

    processed = 0
    embedded = 0
    for listing in listings:
        embedding = await embed_text(
            _embedding_input_text(listing), timeout_seconds=_EMBEDDING_TIMEOUT_SECONDS
        )
        processed += 1
        if embedding is None:
            # Degraded/unavailable provider -- leave embedding_updated_at
            # untouched so this same listing is picked up again on the next
            # invocation rather than being silently skipped forever.
            continue

        listing.description_embedding = embedding
        listing.embedding_updated_at = datetime.now(UTC)
        session.add(listing)
        embedded += 1

    if embedded:
        await session.commit()

    return processed
