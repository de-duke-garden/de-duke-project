"""Request/response Pydantic schemas for the Search & Discovery API
(FEAT-006 Geospatial "Near Me" Search, FEAT-007 Listing Filters & Sort,
FEAT-031 Semantic Property Search -- degraded/keyword-only path).

Kept entirely separate from app/models/listing.py per AGENTS.md ("ORM models
are never reused as API schemas").
"""

from __future__ import annotations

from enum import StrEnum

from pydantic import BaseModel, Field, model_validator


class ListingTypeFilter(StrEnum):
    commercial = "commercial"
    shortlet = "shortlet"


class DealTypeFilter(StrEnum):
    sale = "sale"
    lease = "lease"


class CommercialSubtype(StrEnum):
    """schema.md / FEAT-004: CommercialListing.property_subtype enum."""

    office = "office"
    shop = "shop"
    home = "home"
    land = "land"


class ShortletSubtype(StrEnum):
    """FEAT-005/FEAT-007 shortlet subtypes -- maps directly onto
    ShortletListing.subtype (see app/models/listing.py). Matches
    schema.md's ShortletListing.propertySubtype exactly (hotel|hostel,
    product decision) -- previously also had one/two/three_bedroom members
    duplicating the separate `bedrooms` integer field as a string enum;
    removed rather than left as permanently-dead filter values once
    ListingUpdateIn/ShortletListingIn stopped accepting them."""

    hostel = "hostel"
    hotel = "hotel"


class SortField(StrEnum):
    price = "price"
    distance = "distance"
    newest = "newest"


class SortDirection(StrEnum):
    asc = "asc"
    desc = "desc"


class SearchFilters(BaseModel):
    """All FEAT-007 filter parameters. Every field here must be backed by an
    index per AGENTS.md -- see search_service.py's module docstring for the
    index audit against the current (read-only) models.
    """

    # Location (FEAT-006) -- either device coordinates or a geocoded
    # address/landmark string resolved client-side/upstream to lat/lng before
    # calling this API (geocoding itself is Google Maps API, REPLACE_ME --
    # not implemented here; see search_service.py note).
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    radius_km: float = Field(default=10.0, gt=0, le=200)

    # Free-text query -- FEAT-031 degraded path: keyword-only (ILIKE against
    # title/description), never blocking on an embedding/ranking service.
    query: str | None = Field(default=None, max_length=200)

    listing_type: ListingTypeFilter | None = None
    deal_type: DealTypeFilter | None = None
    commercial_subtype: CommercialSubtype | None = None
    shortlet_subtype: ShortletSubtype | None = None

    min_price: float | None = Field(default=None, ge=0)
    max_price: float | None = Field(default=None, ge=0)

    min_size_sqm: float | None = Field(default=None, ge=0)
    max_size_sqm: float | None = Field(default=None, ge=0)

    bathrooms: int | None = Field(default=None, ge=0)

    amenities: list[str] | None = None
    legal_documents: list[str] | None = None  # Commercial only
    verified_only: bool = False

    sort_by: SortField = SortField.newest
    sort_direction: SortDirection = SortDirection.desc

    @model_validator(mode="after")
    def _validate_ranges(self) -> SearchFilters:
        if (
            self.min_price is not None
            and self.max_price is not None
            and self.min_price > self.max_price
        ):
            raise ValueError("min_price cannot exceed max_price")
        if (
            self.min_size_sqm is not None
            and self.max_size_sqm is not None
            and self.min_size_sqm > self.max_size_sqm
        ):
            raise ValueError("min_size_sqm cannot exceed max_size_sqm")
        if self.sort_by == SortField.distance and (self.latitude is None or self.longitude is None):
            raise ValueError("sort_by=distance requires latitude and longitude")
        if (self.latitude is None) != (self.longitude is None):
            raise ValueError("latitude and longitude must be provided together")
        return self


class ListingSearchResult(BaseModel):
    """Search-result shape shown in Screen 5 (Search Results) listing cards."""

    id: str
    listing_type: ListingTypeFilter
    title: str
    location_city: str
    location_state: str
    location_address_line: str
    latitude: float
    longitude: float
    distance_km: float | None = None

    # Commercial fields (present when listing_type == commercial)
    deal_type: str | None = None
    price: float | None = None
    commercial_subtype: str | None = None
    size_square_meters: float | None = None
    legal_documents: list[str] | None = None

    # Shortlet fields (present when listing_type == shortlet)
    nightly_price: float | None = None
    bedrooms: int | None = None

    amenities: list[str] = Field(default_factory=list)
    is_verified_host: bool = False
    primary_image_url: str | None = None
    created_at: str

    bathrooms: int | None = None


class SearchResponse(BaseModel):
    results: list[ListingSearchResult]
    next_cursor: str | None = None
    has_more: bool = False


class SemanticSearchDegradedInfo(BaseModel):
    """FEAT-031 acceptance criterion: callers must be able to tell when
    ranking degraded to keyword-only so the UI can show an unobtrusive
    "showing keyword results" indicator if desired."""

    semantic_ranking_applied: bool = False
    reason: str | None = None
