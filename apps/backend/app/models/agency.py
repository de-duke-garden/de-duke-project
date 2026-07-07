"""AgencyTeamMember + Lead + LeadAssignment -- schema.md."""

from datetime import UTC, datetime
from uuid import uuid4

from sqlalchemy import DateTime
from sqlmodel import Field, SQLModel

# sa_type=DateTime(timezone=True) throughout this module -- every datetime
# here is timezone-aware UTC (datetime.now(UTC)); without it, SQLModel maps
# plain `datetime` to TIMESTAMP WITHOUT TIME ZONE and asyncpg refuses to
# encode a tz-aware value into a tz-naive column at insert time.


class AgencyTeamMember(SQLModel, table=True):
    __tablename__ = "agency_team_members"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    agency_id: str = Field(foreign_key="users.id", index=True)
    user_id: str = Field(foreign_key="users.id", index=True)
    # admin | agent
    agency_role: str
    invited_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), sa_type=DateTime(timezone=True)
    )
    joined_at: datetime | None = Field(default=None, sa_type=DateTime(timezone=True))


class Lead(SQLModel, table=True):
    __tablename__ = "leads"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    # Cross-store reference: ChatConversation lives in Firestore, resolved by
    # the Backend API Service, not a DB-level foreign key (schema.md storage note).
    conversation_id: str = Field(index=True)
    agency_id: str = Field(foreign_key="users.id", index=True)
    listing_id: str = Field(foreign_key="listings.id", index=True)
    # unassigned | assigned | closed | lost
    status: str = Field(default="unassigned", index=True)
    current_assignment_id: str | None = Field(default=None, foreign_key="lead_assignments.id")
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), sa_type=DateTime(timezone=True)
    )


class LeadAssignment(SQLModel, table=True):
    __tablename__ = "lead_assignments"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    lead_id: str = Field(foreign_key="leads.id", index=True)
    assigned_to_id: str = Field(foreign_key="users.id")
    assigned_by_id: str = Field(foreign_key="users.id")
    assigned_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), sa_type=DateTime(timezone=True)
    )
    unassigned_at: datetime | None = Field(default=None, sa_type=DateTime(timezone=True))
