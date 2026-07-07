"""User -- schema.md `User` entity."""

from datetime import UTC, datetime
from uuid import uuid4

from sqlalchemy import JSON, Column, DateTime
from sqlmodel import Field, SQLModel

# FEAT-024 AC: "User can manage email notification preferences per
# category in settings, separate from push preferences" -- not present in
# schema.md's User entity transcription (confirmed gap, backfilled here,
# same pattern as e.g. CommercialListing.bathrooms's own backfill note).
# One bool per category; missing keys default to enabled (see
# email_service.notify_user), so adding a new category later never
# silently opts existing users out of it.
DEFAULT_EMAIL_NOTIFICATION_PREFERENCES: dict[str, bool] = {
    "account": True,
    "verification": True,
    "payments": True,
}


class User(SQLModel, table=True):
    __tablename__ = "users"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    full_name: str
    email: str | None = Field(default=None, unique=True, index=True)
    phone_number: str | None = Field(default=None, unique=True, index=True)

    # seeker | individual_host | agency | corporate | deduke_staff | deduke_admin
    role: str = Field(index=True)

    # References User.id of the deduke_admin who invited a staff/admin account.
    # Null for the CLI-bootstrapped first admin and for all non-internal roles.
    invited_by_id: str | None = Field(default=None, foreign_key="users.id")

    is_active: bool = Field(default=True)

    # References the most recent HostAccount submission, if any.
    verification_id: str | None = Field(default=None, foreign_key="host_accounts.id")
    is_verified_host: bool = Field(default=False)

    # References the agency User account this user belongs to, if a team member.
    agency_id: str | None = Field(default=None, foreign_key="users.id")

    profile_photo_url: str | None = Field(default=None)
    password_hash: str | None = Field(default=None, exclude=True)

    email_notification_preferences: dict[str, bool] = Field(
        default_factory=lambda: dict(DEFAULT_EMAIL_NOTIFICATION_PREFERENCES),
        sa_column=Column(JSON),
    )

    # sa_type=DateTime(timezone=True) -- every datetime in this codebase is
    # timezone-aware UTC (datetime.now(UTC)); without this, SQLModel maps
    # plain `datetime` to TIMESTAMP WITHOUT TIME ZONE, and asyncpg refuses
    # to encode a tz-aware value into a tz-naive column at insert time.
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), sa_type=DateTime(timezone=True)
    )
    updated_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), sa_type=DateTime(timezone=True)
    )
