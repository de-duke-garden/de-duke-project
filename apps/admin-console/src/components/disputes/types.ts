// Types mirror apps/backend/app/schemas/dispute.py -- FEAT-026.

export type DisputeStatus =
  | "open"
  | "under_review"
  | "resolved_refunded"
  | "resolved_no_refund"
  | "closed";

export type DisputeReason =
  | "property_not_as_described"
  | "incorrect_charge"
  | "service_issue"
  | "other";

export type DisputeResolution = "resolved_refunded" | "resolved_no_refund";

export interface DisputeListItem {
  id: string;
  transaction_id: string;
  raised_by_id: string;
  raised_by_name: string;
  reason: DisputeReason;
  status: DisputeStatus;
  assigned_staff_id: string | null;
  assigned_staff_name: string | null;
  created_at: string;
}

export interface DisputeDetail extends DisputeListItem {
  description: string;
  resolution_notes: string | null;
  refund_amount: number | null;
  resolved_at: string | null;
  listing_id: string;
  transaction_gross_amount: number;
  transaction_status: string;
}

export const REASON_LABELS: Record<DisputeReason, string> = {
  property_not_as_described: "Property not as described",
  incorrect_charge: "Incorrect charge",
  service_issue: "Service issue",
  other: "Other",
};
