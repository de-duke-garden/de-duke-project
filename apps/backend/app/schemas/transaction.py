"""Request/response contracts for FEAT-013/014/027 (checkout, commission,
transaction history)."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class InitiateCheckoutRequest(BaseModel):
    transaction_id: str
    idempotency_key: str = Field(min_length=8, max_length=128)


class InitiateCheckoutResponse(BaseModel):
    transaction_id: str
    status: str
    authorization_url: str
    paystack_reference: str


class PaystackWebhookPayload(BaseModel):
    """Loose envelope -- full Paystack event shape is verified via the
    raw request body + signature, not this parsed model (see
    paystack_webhook_handler.py)."""

    event: str
    data: dict


class TransactionSummary(BaseModel):
    id: str
    listing_id: str
    # Confirmed real gap: every transaction-showing screen (Checkout,
    # Transaction History, Transaction Detail) only ever had `listing_id`
    # to work with, so the client fell back to literally printing the raw
    # id ("Listing 79241f9e-...") instead of the property's actual title.
    # Denormalized onto the response here (rather than requiring the
    # client to make a second GET /v1/listings/{id} call per transaction
    # row) since a transaction's listing title is effectively immutable
    # for display purposes and this is a read-heavy, latency-sensitive
    # screen (checkout).
    listing_title: str
    transaction_type: str
    status: str
    gross_amount: float
    commission_amount: float
    net_payout_amount: float
    possession_period_start_date: datetime | None
    possession_period_end_date: datetime | None
    created_at: datetime


class TransactionDetail(TransactionSummary):
    payer_id: str
    payee_id: str
    payment_processor_reference: str | None
    paid_at: datetime | None
    hold_expires_at: datetime | None
    receipt_url: str | None = None
    # Two-sided commission model (product decision) -- the full breakdown
    # behind gross_amount/net_payout_amount/commission_amount above.
    # Nullable only for legacy transactions predating the split (see
    # migration c9d0e1f2a3b4's backfill for what those hold instead).
    listing_price: float | None = None
    buyer_fee_amount: float | None = None
    owner_commission_amount: float | None = None


class TransactionListResponse(BaseModel):
    items: list[TransactionSummary]
    next_cursor: str | None = None


class CommissionBreakdown(BaseModel):
    """Two-sided breakdown (product decision) -- replaces the old
    single-`rate_percentage` shape, which could only show a blended
    figure derived from commission_amount/gross_amount and couldn't
    distinguish "guest paid extra" from "payee was deducted"."""

    transaction_id: str
    transaction_type: str
    listing_price: float
    buyer_fee_amount: float
    buyer_fee_percentage: float
    owner_commission_amount: float
    owner_commission_percentage: float
    gross_amount: float
    commission_amount: float
    net_payout_amount: float


class CommissionRateRequest(BaseModel):
    transaction_type: str
    # buyer_fee | owner_commission
    fee_type: str
    rate_percentage: float = Field(ge=0, le=100)


class CommissionRateResponse(BaseModel):
    id: str
    transaction_type: str
    fee_type: str
    rate_percentage: float
    set_by_id: str
    effective_from: datetime
    created_at: datetime


class CommissionRateHistoryResponse(BaseModel):
    transaction_type: str
    fee_type: str
    current: CommissionRateResponse | None
    history: list[CommissionRateResponse]
