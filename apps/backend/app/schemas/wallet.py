"""FEAT-043/044/045 -- Escrow release, Wallet, Payout Settings, and
Withdrawal request/response shapes."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


# -- FEAT-043: Admin-Only Escrow Release --------------------------------


class ReleasableTransactionOut(BaseModel):
    """One row in the Admin Web Console's Release Funds screen -- either
    still-escrowed ('payment_received') or already-released
    ('released_to_wallet'), per the `status_filter` the list was fetched
    with. `released_at`/`released_by_admin_id` are always null for a
    still-pending row."""

    transaction_id: str
    listing_id: str
    payer_id: str
    payee_id: str
    transaction_type: str
    gross_amount: float
    commission_amount: float
    net_payout_amount: float
    paid_at: datetime | None
    status: str
    released_at: datetime | None
    released_by_admin_id: str | None
    # FEAT-043/FEAT-026 coupling -- true if a dispute against this
    # transaction is still open/under_review. The Release Funds screen
    # uses this to warn and disable the Release action; the actual
    # enforcement is a hard block in wallet_service.release_transaction,
    # not this flag (never trust client-side gating alone).
    has_open_dispute: bool


class ReleaseFundsResponse(BaseModel):
    transaction_id: str
    status: str
    released_at: datetime | None
    released_by_admin_id: str | None
    net_payout_amount: float


# -- FEAT-044: Host/Agency Virtual Wallet --------------------------------


class WalletOut(BaseModel):
    id: str
    owner_id: str
    balance: float
    currency: str
    updated_at: datetime


class WalletTransactionOut(BaseModel):
    id: str
    direction: str
    amount: float
    source_type: str
    source_id: str | None
    balance_after: float
    notes: str | None
    created_at: datetime


class WalletTransactionListResponse(BaseModel):
    items: list[WalletTransactionOut]
    next_cursor: str | None


# -- FEAT-045: Payout Settings + Withdrawal ------------------------------


class BankOptionOut(BaseModel):
    name: str
    code: str


class PayoutSettingsRequest(BaseModel):
    account_number: str = Field(min_length=10, max_length=10)
    bank_code: str = Field(min_length=1, max_length=16)
    bank_name: str = Field(min_length=1, max_length=128)


class PayoutSettingsResponse(BaseModel):
    id: str
    account_number: str
    bank_code: str
    bank_name: str
    account_holder_name: str
    verification_status: str
    updated_at: datetime


class WithdrawalRequestBody(BaseModel):
    amount: float = Field(gt=0)


class WithdrawalResponse(BaseModel):
    id: str
    wallet_id: str
    amount: float
    status: str
    requested_at: datetime
    paystack_transfer_reference: str | None
    fulfilled_at: datetime | None
    failure_reason: str | None
