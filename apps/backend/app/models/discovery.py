"""SavedSearch + ShareableSummary + ListingAnalytics -- schema.md."""

from datetime import UTC, date, datetime
from uuid import uuid4

from sqlalchemy import DateTime
from sqlmodel import Field, SQLModel

# sa_type=DateTime(timezone=True) throughout this module -- every datetime
# here is timezone-aware UTC (datetime.now(UTC)); without it, SQLModel maps
# plain `datetime` to TIMESTAMP WITHOUT TIME ZONE and asyncpg refuses to
# encode a tz-aware value into a tz-naive column at insert time.


class SavedSearch(SQLModel, table=True):
    __tablename__ = "saved_searches"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    user_id: str = Field(foreign_key="users.id", index=True)
    label: str
    location_query: str
    radius_km: float
    # commercial | shortlet | null
    listing_type: str | None = Field(default=None)
    min_price: float | None = Field(default=None)
    max_price: float | None = Field(default=None)
    verified_only: bool = Field(default=False)
    alerts_enabled: bool = Field(default=False)
    # Best-effort geocode of `location_query` (FEAT-023), resolved once at
    # save time via app/services/geocoding_service.py -- null until/unless
    # geocoding succeeds (unconfigured API key, outage, or unresolvable
    # address all leave this null; matching then degrades to the
    # pre-existing substring match against listing city/state/address,
    # per saved_search_service.py's listing_matches_saved_search).
    location_latitude: float | None = Field(default=None)
    location_longitude: float | None = Field(default=None)
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), sa_type=DateTime(timezone=True)
    )


class ShareableSummary(SQLModel, table=True):
    __tablename__ = "shareable_summaries"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    listing_id: str = Field(foreign_key="listings.id", index=True)
    created_by_id: str = Field(foreign_key="users.id")
    share_token: str = Field(unique=True, index=True)
    is_revoked: bool = Field(default=False)
    expires_at: datetime | None = Field(default=None, sa_type=DateTime(timezone=True))
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), sa_type=DateTime(timezone=True)
    )


class ListingAnalytics(SQLModel, table=True):
    __tablename__ = "listing_analytics"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    listing_id: str = Field(foreign_key="listings.id", index=True)
    range_start: date
    range_end: date
    view_count: int = Field(default=0)
    inquiry_count: int = Field(default=0)
    average_response_time_minutes: float | None = Field(default=None)
    closed_at: datetime | None = Field(default=None, sa_type=DateTime(timezone=True))
