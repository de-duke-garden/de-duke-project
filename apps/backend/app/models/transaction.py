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

    # The listing's own price for this booking/deal, BEFORE either
    # commission component -- product decision (two-sided commission
    # model): the guest pays `listing_price + buyer_fee_amount`
    # (= gross_amount) and the payee's wallet is credited
    # `listing_price - owner_commission_amount` (= net_payout_amount) on
    # release. Nullable only for legacy rows predating this split
    # (backfilled from the old single-rate model's gross_amount, since
    # that model charged exactly the listing price with no buyer fee --
    # see migration f8b1c2d3e4f5's own docstring).
    listing_price: float | None = Field(default=None)
    # gross_amount = listing_price + buyer_fee_amount -- what's actually
    # charged to the guest (the Paystack amount). Computed once, at hold
    # creation (booking_service.confirm_booking), not deferred to payment
    # webhook time -- the charge amount itself must already include the
    # buyer fee before checkout can initiate the Paystack transaction.
    gross_amount: float
    # The surcharge added to listing_price to produce gross_amount.
    # Nullable only for legacy rows (backfilled to 0.0 -- the old model
    # had no separate buyer-side fee at all). Snapshotted from
    # CommissionRateConfig's buyer_fee rate effective at hold-creation
    # time, same "never recomputed later" contract commission_amount
    # already had.
    buyer_fee_amount: float | None = Field(default=None)
    # The amount deducted from listing_price to produce
    # net_payout_amount. Nullable only for legacy rows (backfilled from
    # the old model's single commission_amount, since that model deducted
    # its entire commission from the payee's payout with no buyer-side
    # component).
    owner_commission_amount: float | None = Field(default=None)
    # Total De-Duke revenue on this transaction -- ALWAYS
    # `buyer_fee_amount + owner_commission_amount`, which is also always
    # exactly `gross_amount - net_payout_amount` (both fee components
    # move money between the same two totals, so this identity holds
    # under the old single-rate model too -- existing callers that only
    # ever read `commission_amount` as "the difference between charged
    # and paid out" keep working unmodified).
    commission_amount: float
    net_payout_amount: float
    payment_processor_reference: str | None = Field(default=None, index=True)

    # held | pending_payment | payment_received | released_to_wallet | failed | expired | refunded
    # 'payment_received' is a breaking rename of the former 'succeeded'
    # value (schema.md's Escrow model note) -- funds are confirmed paid
    # and sitting in De-Duke's own Paystack settlement account, but have
    # NOT yet been transferred to the payee. Only 'released_to_wallet'
    # (set exclusively by a De-Duke Admin via FEAT-043, never
    # automatically) means the payee's Wallet has actually been credited.
    status: str = Field(default="held", index=True)

    hold_expires_at: datetime | None = Field(
        default=None, index=True, sa_type=DateTime(timezone=True)
    )
    paid_at: datetime | None = Field(default=None, sa_type=DateTime(timezone=True))
    # Set only when status transitions to 'released_to_wallet' -- always a
    # manual Admin action (FEAT-043), never automated. Null otherwise.
    released_at: datetime | None = Field(default=None, sa_type=DateTime(timezone=True))
    # References the deduke_admin User who performed the release. Only
    # ever a User with role deduke_admin -- Staff cannot release funds.
    released_by_admin_id: str | None = Field(default=None, foreign_key="users.id")
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
