"""Request/response schemas for FEAT-034 (Operations Analytics Dashboard)
and FEAT-035 (Business & Revenue Analytics Dashboard). Loosely-typed dict
fields (e.g. `by_host_type: dict[str, ...]`) mirror the aggregate services'
return shapes directly -- these are read-only reporting endpoints, not
entities with a fixed shape callers write against, so a stricter per-key
schema would add ceremony without a real correctness benefit here.
"""

from typing import Any

from pydantic import BaseModel


class ModerationQueueStatsOut(BaseModel):
    queue_size: int
    avg_age_hours: float
    by_host_type: dict[str, dict[str, Any]]


class DisputeStatsOut(BaseModel):
    open_count: int
    resolved_count: int
    avg_resolution_hours: float


class BookingHoldStatsOut(BaseModel):
    total_holds: int
    hold_to_payment_conversion_rate: float
    hold_expiry_rate: float
    by_status: dict[str, int]


class OperationsDashboardOut(BaseModel):
    moderation_queue: ModerationQueueStatsOut
    host_verification: ModerationQueueStatsOut
    disputes: DisputeStatsOut
    # None -- Firestore-only data, unavailable from the Primary Database
    # (see app/services/ops_analytics_service.py's header docstring).
    support_inbox: None = None
    booking_holds: BookingHoldStatsOut
    staff_workload: dict[str, int]


class ActiveListingsOut(BaseModel):
    by_type: dict[str, int]
    by_status: dict[str, int]
    by_city: dict[str, int]


class ConversionFunnelOut(BaseModel):
    search: int | None = None
    view: int
    inquiry: int
    booking: int


class TransactionTypeRevenueOut(BaseModel):
    gross_transaction_value: float
    commission_revenue: float
    take_rate: float


class RevenueOut(BaseModel):
    by_transaction_type: dict[str, TransactionTypeRevenueOut]
    total_gross_transaction_value: float
    total_commission_revenue: float
    overall_take_rate: float


class BusinessDashboardOut(BaseModel):
    signups_by_role: dict[str, int]
    host_verification_submissions_by_type: dict[str, int]
    active_listings: ActiveListingsOut
    conversion_funnel: ConversionFunnelOut
    revenue: RevenueOut
    # leakage_rate: FEAT-016 now exists (Phase 3) -- see
    # business_analytics_service.leakage_rate's docstring for the exact
    # (approximate) definition; None only when there have been zero
    # inquiries to measure against.
    leakage_rate: float | None = None
