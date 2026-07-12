"""Pydantic response schemas for GET /v1/host/listings -- FEAT-017 (Host
Dashboard). Kept in its own module rather than piling onto
app/schemas/listing.py, since ListingOut's shape (full listing detail) is
not what Screen 12's dashboard cards need -- they need a lighter summary
plus the "zero activity" flag, which is a dashboard-specific concept, not
a Listing model field.
"""

from pydantic import BaseModel


class HostDashboardListingItem(BaseModel):
    """One listing card on Screen 12. `is_stale` is computed server-side
    (see app/services/listing_service.py's list_host_listings) rather than
    left for the client to derive from created_at/view_count/inquiry_count
    -- the "set period" threshold is a business rule that belongs on the
    server, not duplicated in the mobile client.
    """

    id: str
    title: str
    listing_type: str
    status: str
    status_reason: str | None
    view_count: int
    inquiry_count: int
    primary_image_url: str | None
    is_stale: bool


class HostDashboardListingsResponse(BaseModel):
    items: list[HostDashboardListingItem]
