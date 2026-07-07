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
from sqlalchemy import JSON, Column, DateTime, Index
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
    # spatial_index=False -- GeoAlchemy2 otherwise auto-creates its own GiST
    # index ("idx_listings_location_point") as a DDL event the moment
    # CREATE TABLE runs, independent of and in addition to the explicit
    # "ix_listings_location_point_gist" index below, causing a
    # DuplicateTableError the first time this migrated (both target the
    # same column). One explicit, intentionally-named index is enough.
    location_point: str | None = Field(
        default=None,
        sa_column=Column(Geography(geometry_type="POINT", srid=4326, spatial_index=False)),
    )

    amenities: list[str] = Field(default_factory=list, sa_column=Column(JSON))

    # active | under_review | banned | unpublished | closed
    status: str = Field(default="under_review", index=True)
    status_reason: str | None = Field(default=None)

    view_count: int = Field(default=0)

    # sa_type=DateTime(timezone=True) -- every datetime in this codebase is
    # timezone-aware UTC (datetime.now(UTC)); without this, SQLModel maps
    # plain `datetime` to TIMESTAMP WITHOUT TIME ZONE, and asyncpg refuses
    # to encode a tz-aware value into a tz-naive column at insert time.
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), index=True, sa_type=DateTime(timezone=True)
    )
    updated_at: datetime = Field(default_factory=lambda: datetime.now(UTC), sa_type=DateTime(timezone=True))

    # Explicit GiST index for location_point -- required for ST_DWithin/<->
    # performance at scale (FEAT-006/007); not something SQLModel's plain
    # index=True can express for a Geography column.
    __table_args__ = (
        Index("ix_listings_location_point_gist", "location_point", postgresql_using="gist"),
    )


class ListingImage(SQLModel, table=True):
    __tablename__ = "listing_images"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    listing_id: str = Field(foreign_key="listings.id", index=True)
    image_url: str
    display_order: int
    is_primary: bool = Field(default=False)
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC), sa_type=DateTime(timezone=True))


class CommercialListing(SQLModel, table=True):
    __tablename__ = "commercial_listings"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    listing_id: str = Field(foreign_key="listings.id", unique=True)

    # sale | lease
    deal_type: str = Field(index=True)
    price: float = Field(index=True)
    # Null if deal_type == sale. Defaults to 365 if unset on a lease listing.
    possession_period_days: int | None = Field(default=None)
    size_square_meters: float = Field(index=True)
    # office | shop | home | land
    property_subtype: str = Field(index=True)
    # FEAT-007 filter requirement -- added post-Foundation (was missing from
    # the initial schema.md transcription; confirmed gap, backfilled here).
    bathrooms: int = Field(index=True)
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

    nightly_price: float = Field(index=True)
    minimum_stay_nights: int
    maximum_stay_nights: int | None = Field(default=None)
    bedrooms: int
    # FEAT-007 filter requirements -- added post-Foundation (confirmed gaps
    # from the initial schema.md transcription, backfilled here).
    bathrooms: int = Field(index=True)
    # hostel | hotel | 1_bedroom | 2_bedroom | 3_bedroom -- see
    # app/schemas/search.py::ShortletSubtype for the canonical enum values.
    subtype: str = Field(index=True)
    house_rules: list[str] = Field(default_factory=list, sa_column=Column(JSON))
    # ISO date strings (e.g. '2026-08-01') blocked on the availability calendar.
    blocked_dates: list[str] = Field(default_factory=list, sa_column=Column(JSON))
