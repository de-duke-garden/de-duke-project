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
from app.models.listing import ListingMedia
from app.schemas.moderation import (
    ModerationDecisionIn,
    ModerationDecisionOut,
    ModerationQueueItemOut,
    validate_action,
)
from app.services import report_service
from app.services.moderation_service import (
    QUEUE_ITEM_TYPE_CONVERSATION_REPORT,
    QUEUE_ITEM_TYPE_LISTING_REPORT,
    QUEUE_ITEM_TYPE_NEW_LISTING_REVIEW,
    apply_moderation_decision,
    get_listing_or_none,
    list_moderation_queue,
    list_open_reports_for_queue,
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
                select(ListingMedia).where(
                    ListingMedia.listing_id == listing.id,
                    ListingMedia.is_primary == True,  # noqa: E712
                )
            )
        ).scalar_one_or_none()
        items.append(
            ModerationQueueItemOut(
                queue_item_type=QUEUE_ITEM_TYPE_NEW_LISTING_REVIEW,
                listing_id=listing.id,
                listing_type=listing.listing_type,
                title=listing.title,
                status=listing.status,
                status_reason=listing.status_reason,
                host_account_id=listing.host_account_id,
                host_type=host_account.host_type if host_account else "unknown",
                created_at=listing.created_at.isoformat(),
                primary_image_url=primary_image.media_url if primary_image else None,
            )
        )

    # FEAT-025 AC (post-FEAT-009): merge in open/reviewing reports,
    # distinguished via queue_item_type, additive to the original
    # new-Owner-listing review queue above.
    reports = await list_open_reports_for_queue(session)
    for report in reports:
        reporter_name = await report_service.get_user_name_or_unknown(
            session, report.reporter_user_id
        )
        if report.target_type == "listing":
            reported_listing = await get_listing_or_none(session, report.target_id)
            items.append(
                ModerationQueueItemOut(
                    queue_item_type=QUEUE_ITEM_TYPE_LISTING_REPORT,
                    listing_id=reported_listing.id if reported_listing else report.target_id,
                    listing_type=reported_listing.listing_type if reported_listing else None,
                    title=reported_listing.title if reported_listing else None,
                    status=reported_listing.status if reported_listing else None,
                    status_reason=reported_listing.status_reason if reported_listing else None,
                    host_account_id=(
                        reported_listing.host_account_id if reported_listing else None
                    ),
                    host_type=None,
                    created_at=report.created_at.isoformat(),
                    report_id=report.id,
                    report_reason=report.reason,
                    report_detail=report.detail,
                    reporter_user_id=report.reporter_user_id,
                    reporter_name=reporter_name,
                )
            )
        else:
            items.append(
                ModerationQueueItemOut(
                    queue_item_type=QUEUE_ITEM_TYPE_CONVERSATION_REPORT,
                    listing_id=None,
                    listing_type=None,
                    title=None,
                    status=None,
                    status_reason=None,
                    host_account_id=None,
                    host_type=None,
                    created_at=report.created_at.isoformat(),
                    report_id=report.id,
                    report_reason=report.reason,
                    report_detail=report.detail,
                    reporter_user_id=report.reporter_user_id,
                    reporter_name=reporter_name,
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
