"""Staff moderation queue endpoints -- FEAT-025.

All endpoints require DEDUKE_STAFF or DEDUKE_ADMIN role, enforced
server-side via `require_roles` (never hidden via client UI alone).
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, UserRole, require_roles
from app.models.host_account import HostAccount
from app.models.listing import ListingImage
from app.schemas.moderation import (
    ModerationDecisionIn,
    ModerationDecisionOut,
    ModerationQueueItemOut,
    validate_action,
)
from app.services.moderation_service import (
    apply_moderation_decision,
    get_listing_or_none,
    list_moderation_queue,
)

router = APIRouter()

staff_or_admin = require_roles(UserRole.DEDUKE_STAFF, UserRole.DEDUKE_ADMIN)


@router.get("/queue", response_model=list[ModerationQueueItemOut])
async def get_moderation_queue(
    session: AsyncSession = Depends(get_session),
    _current_user: CurrentUser = Depends(staff_or_admin),
) -> list[ModerationQueueItemOut]:
    listings = await list_moderation_queue(session)
    items: list[ModerationQueueItemOut] = []
    for listing in listings:
        host_account = (
            await session.execute(
                select(HostAccount).where(HostAccount.id == listing.host_account_id)
            )
        ).scalar_one_or_none()
        primary_image = (
            await session.execute(
                select(ListingImage).where(
                    ListingImage.listing_id == listing.id,
                    ListingImage.is_primary == True,  # noqa: E712
                )
            )
        ).scalar_one_or_none()
        items.append(
            ModerationQueueItemOut(
                listing_id=listing.id,
                listing_type=listing.listing_type,
                title=listing.title,
                status=listing.status,
                status_reason=listing.status_reason,
                host_account_id=listing.host_account_id,
                host_type=host_account.host_type if host_account else "unknown",
                created_at=listing.created_at.isoformat(),
                primary_image_url=primary_image.image_url if primary_image else None,
            )
        )
    return items


@router.post("/{listing_id}/approve", response_model=ModerationDecisionOut)
async def approve_listing(
    listing_id: str,
    payload: ModerationDecisionIn,
    session: AsyncSession = Depends(get_session),
    _current_user: CurrentUser = Depends(staff_or_admin),
) -> ModerationDecisionOut:
    listing = await get_listing_or_none(session, listing_id)
    if listing is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Listing not found")
    listing = await apply_moderation_decision(
        session, listing=listing, action=validate_action("approve"), reason=payload.reason
    )
    return ModerationDecisionOut(
        listing_id=listing.id, status=listing.status, status_reason=listing.status_reason
    )


@router.post("/{listing_id}/ban", response_model=ModerationDecisionOut)
async def ban_listing(
    listing_id: str,
    payload: ModerationDecisionIn,
    session: AsyncSession = Depends(get_session),
    _current_user: CurrentUser = Depends(staff_or_admin),
) -> ModerationDecisionOut:
    listing = await get_listing_or_none(session, listing_id)
    if listing is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Listing not found")
    listing = await apply_moderation_decision(
        session, listing=listing, action=validate_action("ban"), reason=payload.reason
    )
    return ModerationDecisionOut(
        listing_id=listing.id, status=listing.status, status_reason=listing.status_reason
    )
