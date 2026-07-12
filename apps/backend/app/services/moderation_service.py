"""Staff moderation queue business logic -- FEAT-025.

Handles listing the under_review/flagged queue and recording approve/ban
decisions. Host push notification on a decision is now wired (FEAT-022,
push_service.LISTING_STATUS_CHANGED) -- host EMAIL notification remains a
TODO: no listing-approved/banned email template exists yet in
email_service.py (that module's CATEGORY_BY_TEMPLATE has no equivalent),
so this stays push-only until that template is written; do not fabricate
one here.
"""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.host_account import HostAccount
from app.models.listing import Listing
from app.services import push_service

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

    await _notify_host_of_decision(session, listing=listing, action=action, reason=reason)

    return listing


async def _notify_host_of_decision(
    session: AsyncSession, *, listing: Listing, action: str, reason: str
) -> None:
    """FEAT-022: pushes LISTING_STATUS_CHANGED to the listing's host.
    Email remains a TODO -- see this module's header docstring for why.

    Resolves the host's user_id via Listing -> HostAccount.user_id, same
    walk chat_service.resolve_property_management_id does for the
    non-agency case (this notification is host-specific, not
    agency-aware -- unlike chat's participant resolution, which also
    checks Listing.agency_id, a moderation decision notifies the actual
    HostAccount owner regardless of any agency assignment).
    """
    host_account = await session.get(HostAccount, listing.host_account_id)
    if host_account is None:
        return

    await push_service.notify_user(
        session,
        user_id=host_account.user_id,
        template=push_service.LISTING_STATUS_CHANGED,
        context={"listing_id": listing.id, "action": action, "reason": reason},
    )
