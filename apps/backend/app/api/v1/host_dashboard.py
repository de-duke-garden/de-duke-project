"""GET /v1/host/listings -- FEAT-017 (Host Dashboard, screens.md Screen 12).

Router stays thin; all logic lives in app.services.listing_service per
AGENTS.md. Separate module from app/api/v1/listings.py (which owns listing
CRUD) since this is a dashboard-shaped read, not a listing resource
endpoint -- mounted at its own `/host` prefix (see app/api/v1/__init__.py),
matching screens.md's documented `GET /host/listings` route exactly.
"""

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, get_current_user
from app.models.host_account import HostAccount
from app.schemas.host_dashboard import HostDashboardListingItem, HostDashboardListingsResponse
from app.services.listing_service import list_host_listings

router = APIRouter()


@router.get("/listings", response_model=HostDashboardListingsResponse)
async def get_host_listings(
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> HostDashboardListingsResponse:
    """Screen 12 data need #1 (paired client-side with GET
    /host-accounts/me for verification status, per that screen's Data
    Requirements -- fetched in parallel, not sequentially, from the
    client).

    An unverified host (no HostAccount yet) legitimately has zero listings
    -- returns an empty list rather than a 404/403, since Screen 12's
    Unverified state is driven by the separate /host-accounts/me call, not
    by this endpoint erroring.
    """
    result = await session.execute(
        select(HostAccount).where(HostAccount.user_id == current_user.user_id)
    )
    host_account = result.scalar_one_or_none()
    if host_account is None:
        return HostDashboardListingsResponse(items=[])

    items = await list_host_listings(session, host_account_id=host_account.id)
    return HostDashboardListingsResponse(items=[HostDashboardListingItem(**item) for item in items])
