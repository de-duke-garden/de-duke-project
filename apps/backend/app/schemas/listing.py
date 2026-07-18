"""Pydantic request/response schemas for listing CRUD -- FEAT-004/005.

Multi-file media upload uses the structured contract from architecture.md:
a JSON `media_meta` field (array of {temp_key, display_order, is_primary,
media_type}) submitted alongside multipart file fields named
`file_<temp_key>`. FastAPI's `File(...)` params can't express a dynamic
number of differently-named file fields, so the endpoint parses
`Request.form()` directly instead of taking these as typed parameters --
see app/api/v1/listings.py.

Photos and short video clips (product-shaped, docs/De-Duke/schema.md's
`ListingMedia` entity) share this one upload contract, distinguished by
`MediaMetaIn.media_type` -- video clips are additionally capped at 100MB /
5 minutes / 5 per listing (FEAT-004/FEAT-005 acceptance criteria), enforced
server-side in app/services/listing_service.py, never trusted from the
client alone.
"""

from pydantic import BaseModel, Field, field_validator, model_validator


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


class MediaMetaIn(BaseModel):
    temp_key: str
    display_order: int
    is_primary: bool = False
    # image | video. Defaults to "image" so existing clients built against
    # the pre-video contract (which never sent this field) keep working
    # unchanged.
    media_type: str = "image"

    @field_validator("media_type")
    @classmethod
    def _valid_media_type(cls, v: str) -> str:
        if v not in ("image", "video"):
            raise ValueError("media_type must be 'image' or 'video'")
        return v

    @model_validator(mode="after")
    def _primary_requires_image(self) -> "MediaMetaIn":
        # schema.md's documented invariant: a video can never be a
        # listing's primary/cover -- rejected here (422) rather than
        # silently coerced to False, so a client bug is visible
        # immediately instead of quietly losing the flag. A model-level
        # validator (not a field_validator on is_primary) since it needs
        # both fields already validated, regardless of declaration order.
        if self.is_primary and self.media_type == "video":
            raise ValueError("is_primary cannot be true for media_type='video'")
        return self


class CommercialListingIn(BaseModel):
    deal_type: str  # sale | lease
    price: float = Field(gt=0)
    possession_period_days: int | None = None
    size_square_meters: float = Field(gt=0)
    property_subtype: str  # office | shop | home | land
    legal_documents: list[str] = Field(default_factory=list)
    bathrooms: int = Field(ge=0)
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
    # hostel | hotel -- matches schema.md's ShortletListing.propertySubtype
    # (product decision, docs/De-Duke/schema.md). Previously also accepted
    # 1_bedroom/2_bedroom/3_bedroom, which duplicated the separate
    # `bedrooms` integer field below as a string enum instead of a count --
    # narrowed to just the two real property-subtype values; bedroom count
    # belongs to `bedrooms` alone now.
    subtype: str
    bathrooms: int = Field(ge=0)

    @field_validator("subtype")
    @classmethod
    def _valid_subtype(cls, v: str) -> str:
        allowed = {"hostel", "hotel"}
        if v not in allowed:
            raise ValueError(f"subtype must be one of {sorted(allowed)}")
        return v


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
    # FEAT-004 AC "Host can ... unpublish an existing listing". Deliberately
    # a narrower set than Listing.status's full range (active | under_review
    # | banned | unpublished) -- a host can only toggle their own listing
    # between active and unpublished; under_review/banned are
    # moderation-only outcomes (see moderation_service.apply_moderation_decision),
    # enforced in the endpoint below, not just by this being "the field a
    # well-behaved client happens to send".
    status: str | None = None
    # FEAT-018 AC "originating client/owner" tagging -- see
    # Listing.owner_client_name's docstring. Sending an empty string clears
    # a previously-set tag; `None` (the field simply omitted) leaves it
    # untouched, same partial-update convention as every other field here.
    owner_client_name: str | None = None

    @field_validator("status")
    @classmethod
    def _valid_host_settable_status(cls, v: str | None) -> str | None:
        if v is not None and v not in ("active", "unpublished"):
            raise ValueError("status must be 'active' or 'unpublished'")
        return v


class ListingMediaOut(BaseModel):
    id: str
    media_type: str  # image | video
    media_url: str
    # Video-only -- always None for an image.
    poster_url: str | None = None
    duration_seconds: float | None = None
    # pending | ready | failed | None (None only for legacy/image rows
    # predating this field, where it's meaningless anyway). See
    # ListingMedia.processing_status's own docstring.
    processing_status: str | None = None
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
    inquiry_count: int
    owner_client_name: str | None = None
    # FEAT-042: the owning host's bio/photo/type, closing schema.md's
    # long-documented-but-never-built "shown on their listings" intent for
    # HostAccount.bio. None only if the host account row is somehow
    # missing (defensive -- shouldn't occur for a live listing, since a
    # HostAccount is required to create one at all).
    host_bio: str | None = None
    host_photo_url: str | None = None
    host_type: str | None = None
    media: list[ListingMediaOut] = Field(default_factory=list)
    commercial: dict | None = None
    shortlet: dict | None = None


class AvailabilityQueryIn(BaseModel):
    start_date: str
    end_date: str


class AvailabilityOut(BaseModel):
    listing_id: str
    available: bool
    conflicting_dates: list[str] = Field(default_factory=list)
