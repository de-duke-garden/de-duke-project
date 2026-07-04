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


class TransactionListResponse(BaseModel):
    items: list[TransactionSummary]
    next_cursor: str | None = None


class CommissionBreakdown(BaseModel):
    transaction_id: str
    transaction_type: str
    rate_percentage: float
    gross_amount: float
    commission_amount: float
    net_payout_amount: float


class CommissionRateRequest(BaseModel):
    transaction_type: str
    rate_percentage: float = Field(ge=0, le=100)


class CommissionRateResponse(BaseModel):
    id: str
    transaction_type: str
    rate_percentage: float
    set_by_id: str
    effective_from: datetime
    created_at: datetime


class CommissionRateHistoryResponse(BaseModel):
    transaction_type: str
    current: CommissionRateResponse | None
    history: list[CommissionRateResponse]
