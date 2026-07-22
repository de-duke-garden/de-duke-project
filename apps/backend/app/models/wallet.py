"""Wallet, WalletTransaction, PayoutSettings, WithdrawalRequest --
schema.md's escrow/wallet model (FEAT-043/044/045).

Money flow this module supports: a `Transaction` reaching `payment_received`
sits in De-Duke's own Paystack settlement account as escrow -- no transfer
to the payee has happened yet. A De-Duke Admin manually releases it
(FEAT-043), crediting `Wallet.balance` via an immutable `WalletTransaction`
ledger entry. The payee later requests a `WithdrawalRequest` (FEAT-045),
debiting the wallet immediately and fulfilling automatically via Paystack's
Transfer API against their verified `PayoutSettings` bank account -- no
further Admin approval, since the Admin's release at FEAT-043 was already
the deliberate checkpoint.

One `Wallet`/`PayoutSettings` per payee ROOT (an independent host's own
User, or an agency's root User -- the same account `Listing.agencyId` and
`Transaction.payeeId` already resolve to per `booking_service.py`'s payee
resolution and `agency_service.py`'s `_agency_root_id`), never per invited
agency team member.
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

from app.core.db_types import UTCDateTime
from sqlmodel import Field, SQLModel


class Wallet(SQLModel, table=True):
    __tablename__ = "wallets"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    # Unique -- a User has at most one Wallet (schema.md). Same value space
    # as Transaction.payeeId, so `Wallet.owner_id == txn.payee_id` is
    # exactly the lookup FEAT-043's release action needs -- no separate
    # agency-root resolution required at release time, since payee_id was
    # already resolved to the correct root at booking-creation time (see
    # booking_service.py's payee_id fix).
    owner_id: str = Field(foreign_key="users.id", unique=True, index=True)
    balance: float = Field(default=0.0)
    currency: str = Field(default="NGN")

    created_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), sa_type=UTCDateTime
    )
    updated_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), sa_type=UTCDateTime
    )


class WalletTransaction(SQLModel, table=True):
    __tablename__ = "wallet_transactions"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    wallet_id: str = Field(foreign_key="wallets.id", index=True)

    # credit | debit
    direction: str

    # Always positive; `direction` determines the sign of its effect on
    # balance (schema.md) -- never store a signed amount here.
    amount: float

    # transaction_release | withdrawal | withdrawal_reversal | manual_adjustment
    source_type: str = Field(index=True)
    # References the Transaction (transaction_release) or WithdrawalRequest
    # (withdrawal/withdrawal_reversal) that caused this entry; null for
    # manual_adjustment.
    source_id: str | None = Field(default=None, index=True)

    # Captured at write time for fast historical display without
    # recomputing from the full ledger (schema.md).
    balance_after: float

    # Required for manual_adjustment, optional/null otherwise.
    notes: str | None = Field(default=None)

    # Ledger entries are immutable -- never updated/deleted after creation
    # (schema.md, mirrors AuditLogEntry).
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), sa_type=UTCDateTime
    )


class PayoutSettings(SQLModel, table=True):
    __tablename__ = "payout_settings"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    # Unique -- one active PayoutSettings record per payee root (schema.md).
    owner_id: str = Field(foreign_key="users.id", unique=True, index=True)

    account_number: str
    bank_code: str
    bank_name: str
    # Resolved via Paystack's account resolution API and shown back to the
    # user for confirmation before saving (FEAT-045 AC) -- never
    # user-typed directly.
    account_holder_name: str

    # unverified | verified | failed
    verification_status: str = Field(default="unverified", index=True)

    # Null until the first successful Paystack Transfer Recipient creation;
    # recreated (and this field updated) if the underlying account details
    # change (schema.md).
    paystack_recipient_code: str | None = Field(default=None)

    created_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), sa_type=UTCDateTime
    )
    updated_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), sa_type=UTCDateTime
    )


class WithdrawalRequest(SQLModel, table=True):
    __tablename__ = "withdrawal_requests"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    wallet_id: str = Field(foreign_key="wallets.id", index=True)
    amount: float
    payout_settings_id: str = Field(foreign_key="payout_settings.id")

    # requested | processing | paid | failed
    status: str = Field(default="requested", index=True)

    requested_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), sa_type=UTCDateTime
    )
    requested_by_id: str = Field(foreign_key="users.id")

    # Null while status is 'requested'; populated once the Paystack
    # Transfer API call is made (schema.md).
    paystack_transfer_reference: str | None = Field(default=None, index=True)

    # Null while 'requested'/'processing'; set when a terminal outcome
    # ('paid'/'failed') is reached (schema.md).
    fulfilled_at: datetime | None = Field(default=None, sa_type=UTCDateTime)
    failure_reason: str | None = Field(default=None)
