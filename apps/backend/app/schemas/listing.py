"""Pydantic request/response schemas for listing CRUD -- FEAT-004/005.

Multi-file image upload uses the structured contract from architecture.md:
a JSON `images_meta` field (array of {temp_key, display_order, is_primary})
submitted alongside multipart file fields named `file_<temp_key>`. FastAPI's
`File(...)` params can't express a dynamic number of differently-named file
fields, so the endpoint parses `Request.form()` directly instead of taking
these as typed parameters -- see app/api/v1/listings.py.
"""

from pydantic import BaseModel, Field, field_validator


class LocationIn(BaseModel):
    """Client supplies lat/lng (from any of the three Screen 7 input methods:
    map pin drop, address autocomplete, or GPS "use my location") plus the
    human-readable address fields. The server derives `location_point`
    (PostGIS Geography) from lat/lng -- never accepted directly from the
    client."""

    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    address_line: str
    city: str
    state: str


class ImageMetaIn(BaseModel):
    temp_key: str
    display_order: int
    is_primary: bool = False


class CommercialListingIn(BaseModel):
    deal_type: str  # sale | lease
    price: float = Field(gt=0)
    possession_period_days: int | None = None
    size_square_meters: float = Field(gt=0)
    property_subtype: str  # office | shop | home | land
    legal_documents: list[str] = Field(default_factory=list)
    bathrooms: int | None = Field(
        default=None,
        description=(
            "Not yet a column on CommercialListing -- see GAP note in "
            "listing_service.py. Accepted here for forward-compat but "
            "currently dropped, not persisted."
        ),
    )
    rooms: list["CommercialListingRoomIn"] = Field(default_factory=list)

    @field_validator("deal_type")
    @classmethod
    def _valid_deal_type(cls, v: str) -> str:
        if v not in ("sale", "lease"):
            raise ValueError("deal_type must be 'sale' or 'lease'")
        return v

    @field_validator("property_subtype")
    @classmethod
    def _valid_subtype(cls, v: str) -> str:
        if v not in ("office", "shop", "home", "land"):
            raise ValueError("property_subtype must be office|shop|home|land")
        return v


class CommercialListingRoomIn(BaseModel):
    level: str  # ground | basement | first | second | third
    width_meters: float = Field(gt=0)
    length_meters: float = Field(gt=0)


class ShortletListingIn(BaseModel):
    nightly_price: float = Field(gt=0)
    minimum_stay_nights: int = Field(gt=0)
    maximum_stay_nights: int | None = None
    bedrooms: int = Field(ge=0)
    house_rules: list[str] = Field(default_factory=list)
    blocked_dates: list[str] = Field(default_factory=list)
    subtype: str | None = Field(
        default=None,
        description=(
            "Not yet a column on ShortletListing -- see GAP note in "
            "listing_service.py (FEAT-007 subtype filter: Hostel/Hotel/"
            "1-3BR). Accepted here for forward-compat but currently "
            "dropped, not persisted."
        ),
    )
    bathrooms: int | None = Field(
        default=None,
        description="Not yet a column on ShortletListing -- see GAP note.",
    )


class ListingCreateIn(BaseModel):
    listing_type: str  # commercial | shortlet
    title: str
    description: str
    location: LocationIn
    amenities: list[str] = Field(default_factory=list)
    commercial: CommercialListingIn | None = None
    shortlet: ShortletListingIn | None = None

    @field_validator("listing_type")
    @classmethod
    def _valid_listing_type(cls, v: str) -> str:
        if v not in ("commercial", "shortlet"):
            raise ValueError("listing_type must be 'commercial' or 'shortlet'")
        return v


class ListingUpdateIn(BaseModel):
    title: str | None = None
    description: str | None = None
    location: LocationIn | None = None
    amenities: list[str] | None = None
    commercial: CommercialListingIn | None = None
    shortlet: ShortletListingIn | None = None


class ListingImageOut(BaseModel):
    id: str
    image_url: str
    display_order: int
    is_primary: bool


class ListingOut(BaseModel):
    id: str
    host_account_id: str
    listing_type: str
    title: str
    description: str
    location_latitude: float
    location_longitude: float
    location_address_line: str
    location_city: str
    location_state: str
    amenities: list[str]
    status: str
    status_reason: str | None
    view_count: int
    images: list[ListingImageOut] = Field(default_factory=list)
    commercial: dict | None = None
    shortlet: dict | None = None


class AvailabilityQueryIn(BaseModel):
    start_date: str
    end_date: str


class AvailabilityOut(BaseModel):
    listing_id: str
    available: bool
    conflicting_dates: list[str] = Field(default_factory=list)
