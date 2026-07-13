"""Listing + ListingImage + CommercialListing/CommercialListingRoom +
ShortletListing -- schema.md.

`Listing.location` uses a GeoAlchemy2 Geography column (PostGIS) for
geospatial search (FEAT-006).

FEAT-031 (Semantic Property Search): `description_embedding` is a pgvector
`Vector` column, width `EMBEDDING_DIMENSIONS` (must match
Settings.embedding_dimensions, app/core/config.py -- see
app/services/embedding_service.py for why the default provider is a local,
dependency-free fallback rather than an assumed external vendor). Nullable
and additive (expand-only migration; alembic/versions/<rev>_add_listing_
semantic_search_embedding.py) -- existing rows backfill lazily via
app/workers/listing_embedding_worker.py rather than a blocking migration-time
backfill. `embedding_updated_at` tracks staleness: the worker re-embeds a
listing whenever it is NULL or older than `Listing.updated_at`, satisfying
FEAT-031's "reflected within a few minutes of publish/edit" AC without the
listing write path itself having to block on an embedding call.
"""

from datetime import UTC, datetime
from uuid import uuid4

from geoalchemy2 import Geography
from pgvector.sqlalchemy import Vector
from sqlalchemy import JSON, Column, DateTime, Index
from sqlmodel import Field, SQLModel

# Single source of truth for the embedding column's width -- must stay in
# sync with Settings.embedding_dimensions (app/core/config.py). Duplicated
# as a plain int (not read from get_settings() at import time) because
# Alembic's `env.py` imports this module before any DB/settings context is
# guaranteed ready, and a pgvector Vector column's dimension is fixed at
# migration time regardless of runtime config.
EMBEDDING_DIMENSIONS = 256


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
    # FEAT-017 (Host Dashboard) AC: listing cards show "basic metrics
    # (views, inquiries)". Denormalized counter, same pattern as
    # view_count -- incremented in app/services/chat_service.py's
    # start_conversation, since an "inquiry" is a chat conversation
    # started against this listing (schema.md's Conversation.listing_id).
    inquiry_count: int = Field(default=0)

    # sa_type=DateTime(timezone=True) -- every datetime in this codebase is
    # timezone-aware UTC (datetime.now(UTC)); without this, SQLModel maps
    # plain `datetime` to TIMESTAMP WITHOUT TIME ZONE, and asyncpg refuses
    # to encode a tz-aware value into a tz-naive column at insert time.
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), index=True, sa_type=DateTime(timezone=True)
    )
    updated_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), sa_type=DateTime(timezone=True)
    )

    # FEAT-031 -- see module docstring. Populated asynchronously by
    # app/workers/listing_embedding_worker.py, never computed synchronously
    # on the listing create/update request path.
    description_embedding: list[float] | None = Field(
        default=None,
        sa_column=Column(Vector(EMBEDDING_DIMENSIONS), nullable=True),
    )
    embedding_updated_at: datetime | None = Field(default=None, sa_type=DateTime(timezone=True))

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
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), sa_type=DateTime(timezone=True)
    )


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
