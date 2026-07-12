"""Pydantic schemas for Dispute & Refund Management -- FEAT-026.

Mirrors moderation.py's shape: mobile-facing create request plus
staff/admin-facing list/detail/assign/resolve schemas backing
screens.md Screen 24 (Admin: Dispute & Refund Management).
"""

from datetime import datetime

from pydantic import BaseModel, Field

# Mirrors the reason values documented against app/models/ops.py's
# Dispute.reason column.
DISPUTE_REASONS = (
    "property_not_as_described",
    "incorrect_charge",
    "service_issue",
    "other",
)

# Mirrors the resolution values documented against Dispute.status.
DISPUTE_RESOLUTIONS = ("resolved_refunded", "resolved_no_refund")


class DisputeCreateRequest(BaseModel):
    transaction_id: str
    reason: str
    description: str = Field(min_length=1, max_length=2000)


class DisputeOut(BaseModel):
    """Returned to the mobile client after raising a dispute -- just
    enough to confirm what was recorded, not the full admin-facing shape
    (no assignment/resolution fields a seeker/host has no reason to see
    here; they'd learn the outcome via DISPUTE_RESOLVED push/email)."""

    id: str
    transaction_id: str
    reason: str
    status: str
    created_at: datetime


class DisputeListItemOut(BaseModel):
    id: str
    transaction_id: str
    raised_by_id: str
    raised_by_name: str
    reason: str
    status: str
    assigned_staff_id: str | None
    assigned_staff_name: str | None
    created_at: datetime


class DisputeDetailOut(DisputeListItemOut):
    description: str
    resolution_notes: str | None
    refund_amount: float | None
    resolved_at: datetime | None
    listing_id: str
    transaction_gross_amount: float
    transaction_status: str


class DisputeAssignRequest(BaseModel):
    staff_id: str


class DisputeResolveRequest(BaseModel):
    resolution: str
    resolution_notes: str = Field(min_length=1, max_length=2000)
    # Required only when resolution == "resolved_refunded" -- enforced in
    # dispute_service.resolve_dispute, not here, since the requirement is
    # conditional on another field (Pydantic v2 model_validator territory
    # this project hasn't otherwise adopted; the service-layer check
    # mirrors how host_account.py's per-host-type required fields are
    # validated).
    refund_amount: float | None = None
