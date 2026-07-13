// Mirrors apps/backend/app/schemas/analytics.py -- FEAT-034/FEAT-035.

export interface ModerationQueueStats {
  queue_size: number;
  avg_age_hours: number;
  by_host_type: Record<string, { count: number; avg_age_hours: number }>;
}

export interface DisputeStats {
  open_count: number;
  resolved_count: number;
  avg_resolution_hours: number;
}

export interface BookingHoldStats {
  total_holds: number;
  hold_to_payment_conversion_rate: number;
  hold_expiry_rate: number;
  by_status: Record<string, number>;
}

export interface OperationsDashboard {
  moderation_queue: ModerationQueueStats;
  host_verification: ModerationQueueStats;
  disputes: DisputeStats;
  support_inbox: null;
  booking_holds: BookingHoldStats;
  staff_workload: Record<string, number>;
}

export interface ActiveListings {
  by_type: Record<string, number>;
  by_status: Record<string, number>;
  by_city: Record<string, number>;
}

export interface ConversionFunnel {
  search: number | null;
  view: number;
  inquiry: number;
  booking: number;
}

export interface TransactionTypeRevenue {
  gross_transaction_value: number;
  commission_revenue: number;
  take_rate: number;
}

export interface Revenue {
  by_transaction_type: Record<string, TransactionTypeRevenue>;
  total_gross_transaction_value: number;
  total_commission_revenue: number;
  overall_take_rate: number;
}

export interface BusinessDashboard {
  signups_by_role: Record<string, number>;
  host_verification_submissions_by_type: Record<string, number>;
  active_listings: ActiveListings;
  conversion_funnel: ConversionFunnel;
  revenue: Revenue;
  // FEAT-016 now exists (Phase 3) -- null only when there have been zero
  // inquiries to measure a rate against, see business_analytics_service.py.
  leakage_rate: number | null;
}
