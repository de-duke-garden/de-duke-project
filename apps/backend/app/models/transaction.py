"""Transaction + Receipt -- schema.md."""

from datetime import UTC, datetime
from uuid import uuid4

from sqlalchemy import DateTime
from sqlmodel import Field, SQLModel

# sa_type=DateTime(timezone=True) throughout this module -- every datetime
# here is timezone-aware UTC (datetime.now(UTC)); without it, SQLModel maps
# plain `datetime` to TIMESTAMP WITHOUT TIME ZONE and asyncpg refuses to
# encode a tz-aware value into a tz-naive column at insert time.


class Transaction(SQLModel, table=True):
    __tablename__ = "transactions"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    listing_id: str = Field(foreign_key="listings.id", index=True)
    payer_id: str = Field(foreign_key="users.id", index=True)
    payee_id: str = Field(foreign_key="users.id", index=True)

    # shortlet_booking | lease_deposit | sale_reservation
    transaction_type: str = Field(index=True)

    gross_amount: float
    commission_amount: float
    net_payout_amount: float
    payment_processor_reference: str | None = Field(default=None, index=True)

    # held | pending_payment | succeeded | failed | expired | refunded
    status: str = Field(default="held", index=True)

    hold_expires_at: datetime | None = Field(
        default=None, index=True, sa_type=DateTime(timezone=True)
    )
    paid_at: datetime | None = Field(default=None, sa_type=DateTime(timezone=True))
    possession_period_start_date: datetime | None = Field(
        default=None, sa_type=DateTime(timezone=True)
    )
    possession_period_end_date: datetime | None = Field(
        default=None, index=True, sa_type=DateTime(timezone=True)
    )

    created_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), sa_type=DateTime(timezone=True)
    )


class Receipt(SQLModel, table=True):
    __tablename__ = "receipts"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    transaction_id: str = Field(foreign_key="transactions.id", unique=True)
    receipt_number: str = Field(unique=True, index=True)
    pdf_url: str
    issued_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), sa_type=DateTime(timezone=True)
    )
