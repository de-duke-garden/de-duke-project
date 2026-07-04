// Types mirror apps/backend/app/schemas/moderation.py -- FEAT-025.

export interface ModerationQueueItem {
  listing_id: string;
  listing_type: "commercial" | "shortlet";
  title: string;
  status: string;
  status_reason: string | null;
  host_account_id: string;
  host_type: string;
  created_at: string;
  primary_image_url: string | null;
}

export type ModerationAction = "approve" | "ban";
