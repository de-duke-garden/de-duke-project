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

# FEAT-022 AC: "User can manage notification preferences per category in
# settings" -- push's own category set (listings, chat, payments),
# deliberately DIFFERENT from email's (account, verification, payments)
# per FEAT-024's "separate from push preferences" AC -- see
# app/services/push_service.py's CATEGORY_BY_TEMPLATE for the mapping.
DEFAULT_PUSH_NOTIFICATION_PREFERENCES: dict[str, bool] = {
    "listings": True,
    "chat": True,
    "payments": True,
}


class User(SQLModel, table=True):
    __tablename__ = "users"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    full_name: str
    email: str | None = Field(default=None, unique=True, index=True)
    phone_number: str | None = Field(default=None, unique=True, index=True)

    # "firebase" (guest/host/agency, FEAT-001 --
    # Google Sign-In, Firebase email/password, or Firebase phone/OTP; the
    # Backend API Service never stores a password/OTP for these) |
    # "password" (deduke_staff/deduke_admin only, FEAT-033 -- backend-
    # managed bcrypt password, created via CLI bootstrap or invitation,
    # never through Google/Firebase). See schema.md User.authProvider.
    auth_provider: str = Field(default="password", index=True)
    # Firebase Authentication UID -- set when auth_provider is "firebase",
    # the field POST /v1/auth/firebase-exchange resolves an incoming
    # Firebase ID token to a User record by (creating one on first
    # sign-in). Null for auth_provider "password" accounts.
    firebase_uid: str | None = Field(default=None, unique=True, index=True)

    # guest | host | agency | deduke_staff | deduke_admin
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
    push_notification_preferences: dict[str, bool] = Field(
        default_factory=lambda: dict(DEFAULT_PUSH_NOTIFICATION_PREFERENCES),
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
