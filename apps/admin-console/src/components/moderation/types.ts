// Types mirror apps/backend/app/schemas/moderation.py -- FEAT-025.

// FEAT-025 AC (post-FEAT-009): discriminates "new Owner listing" review
// items from FEAT-009 report items in the same queue.
export type QueueItemType =
  | "new_listing_review"
  | "listing_report"
  | "conversation_report";

export interface ModerationQueueItem {
  queue_item_type: QueueItemType;
  listing_id: string | null;
  listing_type: "commercial" | "shortlet" | null;
  title: string | null;
  status: string | null;
  status_reason: string | null;
  host_account_id: string | null;
  host_type: string | null;
  created_at: string;
  primary_image_url: string | null;

  // Populated only for queue_item_type in (listing_report,
  // conversation_report) -- null for new_listing_review items.
  report_id: string | null;
  report_reason: string | null;
  report_detail: string | null;
  reporter_user_id: string | null;
  reporter_name: string | null;
}

export type ModerationAction = "approve" | "ban";
