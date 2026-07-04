"""User -- schema.md `User` entity."""

from datetime import UTC, datetime
from uuid import uuid4

from sqlmodel import Field, SQLModel


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

    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
