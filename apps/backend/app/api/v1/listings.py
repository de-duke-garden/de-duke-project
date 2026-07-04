"""Listing CRUD + image upload endpoints -- FEAT-004 (Commercial), FEAT-005
(Shortlet), FEAT-008 (auto-approval / under_review status).

Image upload uses the structured multi-file contract from architecture.md:
a JSON `images_meta` form field (array of {temp_key, display_order,
is_primary}) plus multipart file fields named `file_<temp_key>`. FastAPI's
`File(...)` params can't express a dynamic set of differently-named file
fields per request, so these endpoints read `Request.form()` directly.
"""

from __future__ import annotations

import json
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, get_current_user
from app.models.host_account import HostAccount
from app.models.listing import (
    CommercialListing,
    CommercialListingRoom,
    Listing,
    ListingImage,
    ShortletListing,
)
from app.schemas.listing import (
    AvailabilityOut,
    ImageMetaIn,
    ListingCreateIn,
    ListingUpdateIn,
)
from app.services.listing_service import (
    create_commercial_subtype,
    create_listing,
    create_shortlet_subtype,
    is_listing_available,
    listing_to_dict,
    make_location_point_wkt,
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

    images = list(
        (
            await session.execute(
                select(ListingImage).where(ListingImage.listing_id == listing_id)
            )
        )
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

    return listing_to_dict(
        listing,
        images,
        commercial=commercial,
        commercial_rooms=commercial_rooms,
        shortlet=shortlet,
    )


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_listing_endpoint(
    payload: ListingCreateIn,
    session: AsyncSession = Depends(get_session),
    current_user: CurrentUser = Depends(get_current_user),
) -> dict:
    host_account = await _get_own_host_account(session, current_user)
    listing = await create_listing(session, host_account=host_account, payload=payload)
    return await _load_listing_bundle(session, listing.id)


@router.get("/{listing_id}")
async def get_listing_endpoint(
    listing_id: str,
    session: AsyncSession = Depends(get_session),
) -> dict:
    return await _load_listing_bundle(session, listing_id)


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


@router.post("/{listing_id}/images", status_code=status.HTTP_201_CREATED)
async def upload_listing_images_endpoint(
    listing_id: str,
    request: Request,
    session: AsyncSession = Depends(get_session),
    current_user: CurrentUser = Depends(get_current_user),
) -> dict:
    """Structured multi-file upload: `images_meta` (JSON array of
    ImageMetaIn) + one multipart file field per temp_key, named
    `file_<temp_key>`.

    TODO(storage): actual object storage upload (S3 + CDN, per
    infra/modules/s3_cdn) is not wired up in this slice -- no S3 client
    exists yet under app/core. Files are validated and their metadata is
    persisted, but `image_url` is a deterministic placeholder
    (`pending-upload://<listing_id>/<temp_key>`) until that client lands.
    Do not fabricate real bucket/CDN URLs.
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
    raw_meta = form.get("images_meta")
    if raw_meta is None:
        raise HTTPException(status_code=422, detail="images_meta form field is required")

    try:
        meta_list = [ImageMetaIn(**item) for item in json.loads(raw_meta)]
    except (json.JSONDecodeError, ValidationError, TypeError) as exc:
        raise HTTPException(
            status_code=422, detail=f"Invalid images_meta: {exc}"
        ) from exc

    created: list[ListingImage] = []
    for meta in meta_list:
        file_field = f"file_{meta.temp_key}"
        upload_file = form.get(file_field)
        if upload_file is None:
            raise HTTPException(
                status_code=422,
                detail=f"Missing file field '{file_field}' for temp_key '{meta.temp_key}'",
            )
        # TODO(storage): stream `upload_file` (a Starlette UploadFile) to S3
        # here and use the resulting CDN URL instead of the placeholder.
        placeholder_url = f"pending-upload://{listing_id}/{meta.temp_key}"
        image = ListingImage(
            listing_id=listing_id,
            image_url=placeholder_url,
            display_order=meta.display_order,
            is_primary=meta.is_primary,
        )
        session.add(image)
        created.append(image)

    await session.commit()
    return {
        "listing_id": listing_id,
        "images": [
            {
                "id": img.id,
                "image_url": img.image_url,
                "display_order": img.display_order,
                "is_primary": img.is_primary,
            }
            for img in created
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
