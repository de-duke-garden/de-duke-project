"""Staff moderation queue business logic -- FEAT-025.

Handles listing the under_review/flagged queue and recording approve/ban
decisions. Host notification on a decision is a TODO: no notification
provider (FCM/SES) credentials or client are wired up in this slice --
see NOTE below, do not fabricate credentials.
"""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.listing import Listing

MODERATABLE_STATUSES = ("under_review", "flagged")


async def list_moderation_queue(session: AsyncSession) -> list[Listing]:
    """Returns listings awaiting staff action, most recently created first
    (a simple recency-based priority; screens.md Screen 23 leaves detailed
    prioritization logic -- e.g. SLA age -- as a later refinement)."""
    stmt = (
        select(Listing)
        .where(Listing.status.in_(MODERATABLE_STATUSES))
        .order_by(Listing.created_at.asc())
    )
    result = await session.execute(stmt)
    return list(result.scalars().all())


async def get_listing_or_none(session: AsyncSession, listing_id: str) -> Listing | None:
    stmt = select(Listing).where(Listing.id == listing_id)
    result = await session.execute(stmt)
    return result.scalar_one_or_none()


async def apply_moderation_decision(
    session: AsyncSession,
    *,
    listing: Listing,
    action: str,
    reason: str,
) -> Listing:
    """Applies an approve/ban decision to a listing under moderation.

    approve -> status=active, reason cleared (kept for audit as None since
        the model has a single status_reason slot; a full audit trail would
        need a separate moderation_actions table -- out of scope here).
    ban -> status=banned, status_reason=reason.
    """
    if action == "approve":
        listing.status = "active"
        listing.status_reason = None
    elif action == "ban":
        listing.status = "banned"
        listing.status_reason = reason
    else:
        raise ValueError("action must be 'approve' or 'ban'")

    session.add(listing)
    await session.commit()
    await session.refresh(listing)

    # TODO(notifications): notify the host of this moderation decision (push
    # via FCM and/or email via SES) once a notification service/credentials
    # exist. Intentionally not implemented here -- see AGENTS.md: never
    # fabricate third-party provider credentials.
    _notify_host_of_decision(listing, action, reason)

    return listing


def _notify_host_of_decision(listing: Listing, action: str, reason: str) -> None:
    """TODO: wire to the real notification provider (FCM push + SES email)
    once available. Left as a no-op stub deliberately."""
    return None
