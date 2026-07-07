"""Dispute + CommissionRateConfig + AuditLogEntry -- schema.md."""

from datetime import UTC, datetime
from uuid import uuid4

from sqlalchemy import DateTime
from sqlmodel import Field, SQLModel

# sa_type=DateTime(timezone=True) throughout this module -- every datetime
# here is timezone-aware UTC (datetime.now(UTC)); without it, SQLModel maps
# plain `datetime` to TIMESTAMP WITHOUT TIME ZONE and asyncpg refuses to
# encode a tz-aware value into a tz-naive column at insert time.


class Dispute(SQLModel, table=True):
    __tablename__ = "disputes"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    transaction_id: str = Field(foreign_key="transactions.id", index=True)
    raised_by_id: str = Field(foreign_key="users.id")
    # property_not_as_described | incorrect_charge | service_issue | other
    reason: str
    description: str
    # open | under_review | resolved_refunded | resolved_no_refund | closed
    status: str = Field(default="open", index=True)
    assigned_staff_id: str | None = Field(default=None, foreign_key="users.id")
    resolution_notes: str | None = Field(default=None)
    refund_amount: float | None = Field(default=None)
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC), sa_type=DateTime(timezone=True))
    resolved_at: datetime | None = Field(default=None, sa_type=DateTime(timezone=True))


class CommissionRateConfig(SQLModel, table=True):
    __tablename__ = "commission_rate_configs"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    # shortlet_booking | lease_deposit | sale_reservation
    transaction_type: str = Field(index=True)
    rate_percentage: float
    set_by_id: str = Field(foreign_key="users.id")
    effective_from: datetime = Field(index=True, sa_type=DateTime(timezone=True))
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC), sa_type=DateTime(timezone=True))


class AuditLogEntry(SQLModel, table=True):
    """Immutable -- entries are never updated or deleted after creation
    (schema.md). No update/delete service method should ever be written
    against this table."""

    __tablename__ = "audit_log_entries"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    actor_id: str = Field(foreign_key="users.id", index=True)
    action_type: str = Field(index=True)
    # Listing | Dispute | Transaction | CommissionRateConfig | ChatConversation | HostAccount | User
    target_type: str
    target_id: str = Field(index=True)
    notes: str | None = Field(default=None)
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC), sa_type=DateTime(timezone=True))
