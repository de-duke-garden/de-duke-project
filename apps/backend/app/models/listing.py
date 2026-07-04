"""Listing + ListingImage + CommercialListing/CommercialListingRoom +
ShortletListing -- schema.md.

`Listing.location` uses a GeoAlchemy2 Geography column (PostGIS) for
geospatial search (FEAT-006). schema.md's prose also references vector
embeddings for semantic search (FEAT-031), but no embedding field/table is
defined in schema.md's JSON Schema for Listing -- that column is deliberately
left out here rather than invented; it must be specified before Subagent 3
(Search & Discovery) implements FEAT-031.
"""

from datetime import UTC, datetime
from uuid import uuid4

from geoalchemy2 import Geography
from sqlalchemy import JSON, Column
from sqlmodel import Field, SQLModel


class Listing(SQLModel, table=True):
    __tablename__ = "listings"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    host_account_id: str = Field(foreign_key="host_accounts.id", index=True)
    agency_id: str | None = Field(default=None, foreign_key="users.id")

    # commercial | shortlet
    listing_type: str = Field(index=True)

    title: str
    description: str

    # location.* fields inlined per schema.md (small value object)
    location_latitude: float
    location_longitude: float
    location_address_line: str
    location_city: str = Field(index=True)
    location_state: str = Field(index=True)
    # Geography point derived from lat/lng at write time -- indexed (GiST) for
    # FEAT-006 "near me" search. Populated by the listing service, not by the
    # client directly.
    location_point: str | None = Field(
        default=None, sa_column=Column(Geography(geometry_type="POINT", srid=4326))
    )

    amenities: list[str] = Field(default_factory=list, sa_column=Column(JSON))

    # active | under_review | banned | unpublished | closed
    status: str = Field(default="under_review", index=True)
    status_reason: str | None = Field(default=None)

    view_count: int = Field(default=0)

    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(UTC))


class ListingImage(SQLModel, table=True):
    __tablename__ = "listing_images"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    listing_id: str = Field(foreign_key="listings.id", index=True)
    image_url: str
    display_order: int
    is_primary: bool = Field(default=False)
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))


class CommercialListing(SQLModel, table=True):
    __tablename__ = "commercial_listings"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    listing_id: str = Field(foreign_key="listings.id", unique=True)

    # sale | lease
    deal_type: str
    price: float
    # Null if deal_type == sale. Defaults to 365 if unset on a lease listing.
    possession_period_days: int | None = Field(default=None)
    size_square_meters: float
    # office | shop | home | land
    property_subtype: str = Field(index=True)
    legal_documents: list[str] = Field(default_factory=list, sa_column=Column(JSON))


class CommercialListingRoom(SQLModel, table=True):
    __tablename__ = "commercial_listing_rooms"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    commercial_listing_id: str = Field(foreign_key="commercial_listings.id", index=True)
    # ground | basement | first | second | third
    level: str
    width_meters: float
    length_meters: float


class ShortletListing(SQLModel, table=True):
    __tablename__ = "shortlet_listings"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    listing_id: str = Field(foreign_key="listings.id", unique=True)

    nightly_price: float
    minimum_stay_nights: int
    maximum_stay_nights: int | None = Field(default=None)
    bedrooms: int
    house_rules: list[str] = Field(default_factory=list, sa_column=Column(JSON))
    # ISO date strings (e.g. '2026-08-01') blocked on the availability calendar.
    blocked_dates: list[str] = Field(default_factory=list, sa_column=Column(JSON))
