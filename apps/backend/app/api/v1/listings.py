"""Listing CRUD + media (photo/video) upload endpoints -- FEAT-004
(Commercial), FEAT-005 (Shortlet), FEAT-008 (auto-approval / under_review
status).

Media upload uses the structured multi-file contract from architecture.md:
a JSON `media_meta` form field (array of {temp_key, display_order,
is_primary, media_type}) plus multipart file fields named `file_<temp_key>`.
FastAPI's `File(...)` params can't express a dynamic set of
differently-named file fields per request, so these endpoints read
`Request.form()` directly.

A video clip (media_type='video') is additionally probed for duration and
has a poster frame extracted server-side (app/services/listing_service.py's
process_uploaded_video) -- rejected outright if it exceeds
MAX_VIDEO_BYTES/MAX_VIDEO_DURATION_SECONDS or the listing would exceed
MAX_VIDEOS_PER_LISTING (FEAT-004/FEAT-005 acceptance criteria), degraded
gracefully (stored with processing_status='failed', no poster) if ffmpeg/
ffprobe merely can't process an otherwise-valid file.
"""

from __future__ import annotations

import json
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, get_current_user, get_current_user_optional
from app.core.storage import upload_bytes as upload_bytes_to_media_storage
from app.core.storage import upload_file as upload_to_media_storage
from app.models.host_account import HostAccount
from app.models.listing import (
    CommercialListing,
    CommercialListingRoom,
    Listing,
    ListingMedia,
    ShortletListing,
)
from app.schemas.listing import (
    AvailabilityOut,
    ListingCreateIn,
    ListingUpdateIn,
    MediaMetaIn,
)
from app.services import agency_service, analytics_service
from app.services.listing_service import (
    MAX_VIDEO_BYTES,
    MAX_VIDEO_DURATION_SECONDS,
    MAX_VIDEOS_PER_LISTING,
    count_listing_videos,
    create_commercial_subtype,
    create_listing,
    create_shortlet_subtype,
    increment_view_count,
    is_listing_available,
    listing_to_dict,
    make_location_point_wkt,
    process_uploaded_video,
    touch_updated_at,
)

router = APIRouter()


async def _get_own_host_account(session: AsyncSession, current_user: CurrentUser) -> HostAccount:
    stmt = select(HostAccount).where(HostAccount.user_id == current_user.user_id)
    result = await session.execute(stmt)
    host_account = result.scalar_one_or_none()
    if host_account is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="A verified host account is required to create listings.",
        )
    return host_account


async def _load_listing_bundle(session: AsyncSession, listing_id: str) -> dict:
    listing = (
        await session.execute(select(Listing).where(Listing.id == listing_id))
    ).scalar_one_or_none()
    if listing is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Listing not found")

    media = list(
        (await session.execute(select(ListingMedia).where(ListingMedia.listing_id == listing_id)))
        .scalars()
        .all()
    )

    commercial = None
    commercial_rooms: list[CommercialListingRoom] = []
    shortlet = None
    if listing.listing_type == "commercial":
        commercial = (
            await session.execute(
                select(CommercialListing).where(CommercialListing.listing_id == listing_id)
            )
        ).scalar_one_or_none()
        if commercial is not None:
            commercial_rooms = list(
                (
                    await session.execute(
                        select(CommercialListingRoom).where(
                            CommercialListingRoom.commercial_listing_id == commercial.id
                        )
                    )
                )
                .scalars()
                .all()
            )
    elif listing.listing_type == "shortlet":
        shortlet = (
            await session.execute(
                select(ShortletListing).where(ShortletListing.listing_id == listing_id)
            )
        ).scalar_one_or_none()

    # FEAT-042: Host Profile card (mobile Listing Detail) + Admin Web
    # Console Chat Oversight property context both need the owning host's
    # bio/photo/type -- fetched here, once, alongside everything else this
    # bundle already assembles.
    host_account = (
        await session.execute(
            select(HostAccount).where(HostAccount.id == listing.host_account_id)
        )
    ).scalar_one_or_none()

    return listing_to_dict(
        listing,
        media,
        commercial=commercial,
        commercial_rooms=commercial_rooms,
        shortlet=shortlet,
        host_account=host_account,
    )


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_listing_endpoint(
    payload: ListingCreateIn,
    session: AsyncSession = Depends(get_session),
    current_user: CurrentUser = Depends(get_current_user),
) -> dict:
    host_account = await _get_own_host_account(session, current_user)
    # None for an individual host; the agency root's users.id for an
    # agency account (root or invited team member) -- see
    # agency_service.resolve_agency_id_for_listing's docstring for the bug
    # this fixes (agency listings never showing in their own Portfolio).
    agency_id = await agency_service.resolve_agency_id_for_listing(session, current_user)
    listing = await create_listing(
        session, host_account=host_account, payload=payload, agency_id=agency_id
    )
    return await _load_listing_bundle(session, listing.id)


@router.get("/{listing_id}")
async def get_listing_endpoint(
    listing_id: str,
    session: AsyncSession = Depends(get_session),
    current_user: CurrentUser | None = Depends(get_current_user_optional),
) -> dict:
    bundle = await _load_listing_bundle(session, listing_id)
    # Fire-and-forget-ish, but still awaited -- see increment_view_count's
    # docstring for why this is a direct UPDATE, not a read-modify-write.
    # Deliberately after _load_listing_bundle (which 404s on a missing
    # listing) so a bad ID never increments anything.
    await increment_view_count(session, listing_id)
    await analytics_service.track_event(
        event_name=analytics_service.LISTING_VIEWED,
        user_id=current_user.user_id if current_user else None,
        properties={"listing_id": listing_id},
    )
    return bundle


@router.patch("/{listing_id}")
async def update_listing_endpoint(
    listing_id: str,
    payload: ListingUpdateIn,
    session: AsyncSession = Depends(get_session),
    current_user: CurrentUser = Depends(get_current_user),
) -> dict:
    listing = (
        await session.execute(select(Listing).where(Listing.id == listing_id))
    ).scalar_one_or_none()
    if listing is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Listing not found")

    host_account = await _get_own_host_account(session, current_user)
    if listing.host_account_id != host_account.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only edit your own listings.",
        )

    if payload.title is not None:
        listing.title = payload.title
    if payload.description is not None:
        listing.description = payload.description
    if payload.location is not None:
        listing.location_latitude = payload.location.latitude
        listing.location_longitude = payload.location.longitude
        listing.location_address_line = payload.location.address_line
        listing.location_city = payload.location.city
        listing.location_state = payload.location.state
        listing.location_point = make_location_point_wkt(
            payload.location.latitude, payload.location.longitude
        )
    if payload.amenities is not None:
        listing.amenities = payload.amenities
    if payload.owner_client_name is not None:
        listing.owner_client_name = payload.owner_client_name or None
    if payload.status is not None:
        # ListingUpdateIn's validator already restricts payload.status to
        # {"active", "unpublished"}; the remaining guard here is that a
        # host can only toggle between those two states themselves -- a
        # listing currently under_review or banned stays that way until
        # staff act on it (moderation_service.apply_moderation_decision),
        # regardless of what the host's own PATCH request asks for.
        if listing.status not in ("active", "unpublished"):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Cannot change status while listing is {listing.status}.",
            )
        listing.status = payload.status
    touch_updated_at(listing)
    session.add(listing)

    if payload.commercial is not None and listing.listing_type == "commercial":
        existing = (
            await session.execute(
                select(CommercialListing).where(CommercialListing.listing_id == listing_id)
            )
        ).scalar_one_or_none()
        if existing is not None:
            await session.delete(existing)
            await session.flush()
        await create_commercial_subtype(session, listing_id, payload.commercial)

    if payload.shortlet is not None and listing.listing_type == "shortlet":
        existing_shortlet = (
            await session.execute(
                select(ShortletListing).where(ShortletListing.listing_id == listing_id)
            )
        ).scalar_one_or_none()
        if existing_shortlet is not None:
            existing_shortlet.nightly_price = payload.shortlet.nightly_price
            existing_shortlet.minimum_stay_nights = payload.shortlet.minimum_stay_nights
            existing_shortlet.maximum_stay_nights = payload.shortlet.maximum_stay_nights
            existing_shortlet.bedrooms = payload.shortlet.bedrooms
            existing_shortlet.house_rules = payload.shortlet.house_rules
            existing_shortlet.blocked_dates = payload.shortlet.blocked_dates
            session.add(existing_shortlet)
        else:
            create_shortlet_subtype(session, listing_id, payload.shortlet)

    await session.commit()
    return await _load_listing_bundle(session, listing_id)


@router.post("/{listing_id}/media", status_code=status.HTTP_201_CREATED)
async def upload_listing_media_endpoint(
    listing_id: str,
    request: Request,
    session: AsyncSession = Depends(get_session),
    current_user: CurrentUser = Depends(get_current_user),
) -> dict:
    """Structured multi-file upload: `media_meta` (JSON array of
    MediaMetaIn) + one multipart file field per temp_key, named
    `file_<temp_key>`. Each file is uploaded to the File Storage Service
    (S3 + CDN, app/core/storage.py) and its durable CDN URL persisted.

    A `media_type='video'` item is additionally validated against
    MAX_VIDEO_BYTES/MAX_VIDEO_DURATION_SECONDS/MAX_VIDEOS_PER_LISTING
    BEFORE upload (so a rejected clip never touches File Storage), then has
    its duration probed and a poster frame extracted server-side
    (listing_service.process_uploaded_video) -- a processing failure there
    degrades to `processing_status='failed'` rather than rejecting the
    upload outright, since the video itself is still valid and playable,
    just without a poster (see that function's docstring).
    """
    listing = (
        await session.execute(select(Listing).where(Listing.id == listing_id))
    ).scalar_one_or_none()
    if listing is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Listing not found")

    host_account = await _get_own_host_account(session, current_user)
    if listing.host_account_id != host_account.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not your listing.")

    form = await request.form()
    raw_meta = form.get("media_meta")
    if raw_meta is None:
        raise HTTPException(status_code=422, detail="media_meta form field is required")

    try:
        meta_list = [MediaMetaIn(**item) for item in json.loads(raw_meta)]
    except (json.JSONDecodeError, ValidationError, TypeError) as exc:
        raise HTTPException(status_code=422, detail=f"Invalid media_meta: {exc}") from exc

    new_video_count = sum(1 for meta in meta_list if meta.media_type == "video")
    if new_video_count:
        existing_video_count = await count_listing_videos(session, listing_id)
        if existing_video_count + new_video_count > MAX_VIDEOS_PER_LISTING:
            raise HTTPException(
                status_code=422,
                detail=(
                    f"A listing can have at most {MAX_VIDEOS_PER_LISTING} videos "
                    f"(already has {existing_video_count})."
                ),
            )

    created: list[ListingMedia] = []
    for meta in meta_list:
        file_field = f"file_{meta.temp_key}"
        upload_file = form.get(file_field)
        if upload_file is None or isinstance(upload_file, str):
            raise HTTPException(
                status_code=422,
                detail=f"Missing file field '{file_field}' for temp_key '{meta.temp_key}'",
            )

        if meta.media_type == "video":
            video_bytes = await upload_file.read()
            if len(video_bytes) > MAX_VIDEO_BYTES:
                raise HTTPException(
                    status_code=422,
                    detail=(
                        f"Video '{meta.temp_key}' exceeds the "
                        f"{MAX_VIDEO_BYTES // (1024 * 1024)}MB limit."
                    ),
                )

            duration_seconds, poster_bytes = await process_uploaded_video(video_bytes)
            if duration_seconds is not None and duration_seconds > MAX_VIDEO_DURATION_SECONDS:
                raise HTTPException(
                    status_code=422,
                    detail=(
                        f"Video '{meta.temp_key}' exceeds the "
                        f"{MAX_VIDEO_DURATION_SECONDS // 60}-minute limit."
                    ),
                )

            content_type = upload_file.content_type or "video/mp4"
            media_url = await upload_bytes_to_media_storage(
                video_bytes,
                prefix=f"listings/{listing_id}",
                filename=upload_file.filename or "video.mp4",
                content_type=content_type,
            )
            poster_url = None
            if poster_bytes is not None:
                poster_url = await upload_bytes_to_media_storage(
                    poster_bytes,
                    prefix=f"listings/{listing_id}/posters",
                    filename="poster.jpg",
                    content_type="image/jpeg",
                )

            item = ListingMedia(
                listing_id=listing_id,
                media_type="video",
                media_url=media_url,
                poster_url=poster_url,
                duration_seconds=duration_seconds,
                processing_status="ready" if poster_url is not None else "failed",
                display_order=meta.display_order,
                is_primary=False,  # MediaMetaIn's own validator already enforces this
            )
        else:
            media_url = await upload_to_media_storage(
                upload_file, prefix=f"listings/{listing_id}"
            )
            item = ListingMedia(
                listing_id=listing_id,
                media_type="image",
                media_url=media_url,
                processing_status="ready",
                display_order=meta.display_order,
                is_primary=meta.is_primary,
            )
        session.add(item)
        created.append(item)

    await session.commit()
    return {
        "listing_id": listing_id,
        "media": [
            {
                "id": item.id,
                "media_type": item.media_type,
                "media_url": item.media_url,
                "poster_url": item.poster_url,
                "duration_seconds": item.duration_seconds,
                "processing_status": item.processing_status,
                "display_order": item.display_order,
                "is_primary": item.is_primary,
            }
            for item in created
        ],
    }


@router.get("/{listing_id}/availability", response_model=AvailabilityOut)
async def get_listing_availability_endpoint(
    listing_id: str,
    start_date: date,
    end_date: date,
    session: AsyncSession = Depends(get_session),
) -> AvailabilityOut:
    listing = (
        await session.execute(select(Listing).where(Listing.id == listing_id))
    ).scalar_one_or_none()
    if listing is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Listing not found")

    available, conflicts = await is_listing_available(
        session, listing_id=listing_id, start_date=start_date, end_date=end_date
    )
    return AvailabilityOut(listing_id=listing_id, available=available, conflicting_dates=conflicts)
