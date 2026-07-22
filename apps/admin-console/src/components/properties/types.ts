// Mirrors apps/backend/app/schemas/listing.py's ListingSummaryOut/
// ListingListResponse (the admin-only GET /v1/listings list).

export interface ListingSummary {
  id: string;
  title: string;
  listing_type: "commercial" | "shortlet";
  status: string;
  status_reason: string | null;
  location_city: string;
  location_state: string;
  primary_image_url: string | null;
}

export interface ListingListResponse {
  items: ListingSummary[];
  next_cursor: string | null;
}

export const LISTING_STATUS_FILTERS: { value: string; label: string }[] = [
  { value: "", label: "All statuses" },
  { value: "active", label: "Active" },
  { value: "under_review", label: "Under review" },
  { value: "flagged", label: "Flagged" },
  { value: "banned", label: "Banned" },
  { value: "unpublished", label: "Unpublished" },
  { value: "closed", label: "Closed" },
];

export const LISTING_TYPE_FILTERS: { value: string; label: string }[] = [
  { value: "", label: "All types" },
  { value: "commercial", label: "Commercial" },
  { value: "shortlet", label: "Shortlet" },
];

export const LISTING_STATUS_TONE: Record<
  string,
  "success" | "warning" | "error" | "neutral"
> = {
  active: "success",
  under_review: "warning",
  flagged: "warning",
  banned: "error",
  unpublished: "neutral",
  closed: "neutral",
};
