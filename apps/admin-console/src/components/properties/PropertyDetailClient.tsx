"use client";

import { useEffect, useState } from "react";
import Link from "next/link";

import { StatusBadge } from "@/components/ui/StatusBadge";
import { TableSkeleton } from "@/components/ui/Skeleton";
import { LISTING_STATUS_TONE } from "./types";

const API_BASE_URL = "/api/backend/v1";

type LoadState = "loading" | "loaded" | "error";

/** Full shape of GET /v1/listings/:id's response (app/schemas/listing.py's
 * ListingOut / listing_to_dict) -- every field it returns is already
 * staff/guest-safe (it's the same payload the mobile app's public Listing
 * Detail screen renders); the only things deliberately NOT in this
 * interface are fields the backend itself never serializes onto ListingOut
 * at all -- `description_embedding`/`embedding_updated_at` (internal
 * semantic-search vector/staleness bookkeeping) and the raw
 * `location_point` PostGIS WKT string (internal geospatial-index
 * representation, redundant with the lat/lng already below) -- neither
 * reaches this response, so there is nothing to filter client-side.
 */
interface ListingMediaItem {
  id: string;
  media_type: "image" | "video";
  media_url: string;
  poster_url: string | null;
  duration_seconds: number | null;
  processing_status: string | null;
  display_order: number;
  is_primary: boolean;
}

interface CommercialDetail {
  deal_type: string;
  price: number;
  possession_period_days: number;
  size_square_meters: number;
  property_subtype: string;
  legal_documents: string[];
  rooms: { level: string; width_meters: number; length_meters: number }[];
}

interface ShortletDetail {
  nightly_price: number;
  minimum_stay_nights: number;
  maximum_stay_nights: number;
  bedrooms: number;
  house_rules: string;
  blocked_dates: string[];
}

interface ListingDetail {
  id: string;
  host_account_id: string;
  listing_type: "commercial" | "shortlet";
  title: string;
  description: string;
  location_latitude: number;
  location_longitude: number;
  location_address_line: string;
  location_city: string;
  location_state: string;
  amenities: string[];
  status: string;
  status_reason: string | null;
  view_count: number;
  inquiry_count: number;
  owner_client_name: string | null;
  host_bio: string | null;
  host_photo_url: string | null;
  host_type: string | null;
  media: ListingMediaItem[];
  commercial: CommercialDetail | null;
  shortlet: ShortletDetail | null;
}

async function fetchListing(id: string): Promise<ListingDetail> {
  const response = await fetch(`${API_BASE_URL}/listings/${id}`);
  if (!response.ok) {
    throw new Error(`Failed to load this property (${response.status})`);
  }
  return response.json();
}

// Returns null (rendered as "--") rather than 0 on a failed/forbidden
// fetch -- Release Funds counts are Admin-only server-side, so a Staff
// viewer legitimately gets a 403 here; that must read as "not visible to
// you", not "zero", same distinction StatusBadge-style summary cards
// elsewhere in this console make between an empty state and a load failure.
async function fetchCount(url: string): Promise<number | null> {
  const response = await fetch(url);
  if (!response.ok) return null;
  const body = await response.json();
  return Array.isArray(body) ? body.length : null;
}

/** `/properties/:id` -- the context hub other admin console screens
 * (Disputes, Moderation Queue, Release Funds, Conversations) deep-link a
 * listing_id into. Shows the FULL property record (every field
 * GET /v1/listings/:id returns -- see ListingDetail's own docstring for
 * what's deliberately excluded and why), but stays a summary-counts +
 * "View all" links hub for RELATED ACTIVITY specifically -- it does NOT
 * re-implement any of those other screens' own interactive workflows
 * (assign/resolve a dispute, approve/ban a listing, release funds, join a
 * conversation), which stay owned by their own screens, reached from here
 * pre-filtered to this one listing.
 */
export function PropertyDetailClient({ listingId }: { listingId: string }) {
  const [state, setState] = useState<LoadState>("loading");
  const [listing, setListing] = useState<ListingDetail | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const [disputeCount, setDisputeCount] = useState<number | null>(null);
  const [moderationCount, setModerationCount] = useState<number | null>(null);
  const [pendingReleaseCount, setPendingReleaseCount] = useState<number | null>(null);
  const [releasedCount, setReleasedCount] = useState<number | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      setState("loading");
      try {
        const data = await fetchListing(listingId);
        if (cancelled) return;
        setListing(data);
        setState("loaded");
      } catch (e) {
        if (cancelled) return;
        setErrorMessage(e instanceof Error ? e.message : "Something went wrong.");
        setState("error");
        return;
      }

      // Best-effort, independent of the critical listing fetch above --
      // a summary count failing to load shouldn't block the rest of the
      // page (each card just shows "--" instead of a number).
      void fetchCount(`${API_BASE_URL}/disputes?listing_id=${listingId}`).then(
        (n) => !cancelled && setDisputeCount(n),
      );
      void fetchCount(`${API_BASE_URL}/moderation/queue?listing_id=${listingId}`).then(
        (n) => !cancelled && setModerationCount(n),
      );
      void fetchCount(
        `${API_BASE_URL}/wallet/admin/releasable?status_filter=pending&listing_id=${listingId}`,
      ).then((n) => !cancelled && setPendingReleaseCount(n));
      void fetchCount(
        `${API_BASE_URL}/wallet/admin/releasable?status_filter=released&listing_id=${listingId}`,
      ).then((n) => !cancelled && setReleasedCount(n));
    }

    void load();
    return () => {
      cancelled = true;
    };
  }, [listingId]);

  if (state === "loading") {
    return <TableSkeleton rows={4} columns={2} />;
  }

  if (state === "error" || listing === null) {
    return (
      <div className="rounded-md border border-error p-md">
        <p className="text-error">{errorMessage ?? "Property not found."}</p>
        <Link href="/properties" className="mt-sm inline-block text-sm underline">
          Back to Properties
        </Link>
      </div>
    );
  }

  const price = listing.commercial
    ? `₦${listing.commercial.price.toLocaleString()}`
    : listing.shortlet
      ? `₦${listing.shortlet.nightly_price.toLocaleString()}/night`
      : null;
  const sortedMedia = [...listing.media].sort((a, b) => a.display_order - b.display_order);
  const primaryImage = sortedMedia.find((m) => m.is_primary) ?? sortedMedia[0];

  return (
    <div className="space-y-lg">
      <div className="rounded-lg border border-border p-lg dark:border-border-dark">
        <div className="flex flex-wrap items-start justify-between gap-md">
          <div>
            <h2 className="font-heading text-lg font-semibold">{listing.title}</h2>
            <p className="text-sm text-text-secondary">
              {[listing.location_address_line, listing.location_city, listing.location_state]
                .filter(Boolean)
                .join(", ")}
            </p>
            <p className="mt-xs text-xs text-text-secondary">
              {listing.location_latitude.toFixed(5)}, {listing.location_longitude.toFixed(5)}
            </p>
          </div>
          <div className="flex items-center gap-sm">
            <StatusBadge
              value={listing.status}
              label={listing.status.replace(/_/g, " ")}
              tone={LISTING_STATUS_TONE[listing.status] ?? "neutral"}
            />
            <span className="text-xs capitalize text-text-secondary">{listing.listing_type}</span>
          </div>
        </div>

        {listing.status_reason && (
          <p className="mt-sm text-sm text-error">Reason: {listing.status_reason}</p>
        )}

        {primaryImage && (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={primaryImage.poster_url ?? primaryImage.media_url}
            alt=""
            className="mt-md h-56 w-full rounded-md object-cover"
          />
        )}

        {/* Full media gallery -- every photo/video, not just the primary
            shown above. Videos render via their poster frame with a play
            badge (this console doesn't embed a video player) rather than
            being silently dropped from the gallery. */}
        {sortedMedia.length > 1 && (
          <div className="mt-sm grid grid-cols-3 gap-xs sm:grid-cols-4 md:grid-cols-6">
            {sortedMedia.map((m) => (
              <div key={m.id} className="relative aspect-square overflow-hidden rounded-md">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={m.poster_url ?? m.media_url}
                  alt=""
                  className="h-full w-full object-cover"
                />
                {m.media_type === "video" && (
                  <span className="absolute inset-0 flex items-center justify-center bg-black/30 text-white">
                    ▶
                  </span>
                )}
                {m.is_primary && (
                  <span className="absolute bottom-1 left-1 rounded bg-black/60 px-1 text-[10px] text-white">
                    Primary
                  </span>
                )}
              </div>
            ))}
          </div>
        )}

        {price && <p className="mt-md text-lg font-semibold">{price}</p>}
        <p className="mt-sm whitespace-pre-wrap text-sm text-text-secondary">
          {listing.description}
        </p>

        {listing.amenities.length > 0 && (
          <div className="mt-md">
            <p className="text-xs font-medium uppercase text-text-secondary">Amenities</p>
            <div className="mt-xs flex flex-wrap gap-xs">
              {listing.amenities.map((a) => (
                <span
                  key={a}
                  className="rounded-full bg-surface-secondary px-sm py-0.5 text-xs dark:bg-surface-secondary-dark"
                >
                  {a}
                </span>
              ))}
            </div>
          </div>
        )}

        <div className="mt-md grid grid-cols-2 gap-sm text-sm sm:grid-cols-4">
          <Stat label="Views" value={listing.view_count} />
          <Stat label="Inquiries" value={listing.inquiry_count} />
          {listing.owner_client_name && (
            <div>
              <p className="text-xs uppercase text-text-secondary">Owner/client</p>
              <p>{listing.owner_client_name}</p>
            </div>
          )}
        </div>

        {listing.host_bio && (
          <div className="mt-md flex items-start gap-sm rounded-md border border-border p-md dark:border-border-dark">
            {listing.host_photo_url && (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={listing.host_photo_url}
                alt=""
                className="h-10 w-10 shrink-0 rounded-full object-cover"
              />
            )}
            <div>
              <p className="text-xs font-medium uppercase text-text-secondary">
                Host ({listing.host_type ?? "unknown"}) &middot; {listing.host_account_id}
              </p>
              <p className="mt-xs text-sm">{listing.host_bio}</p>
            </div>
          </div>
        )}
      </div>

      {listing.commercial && (
        <div className="rounded-lg border border-border p-lg dark:border-border-dark">
          <h3 className="font-heading text-base font-semibold">Commercial deal details</h3>
          <div className="mt-sm grid grid-cols-2 gap-sm text-sm sm:grid-cols-4">
            <Stat label="Deal type" value={listing.commercial.deal_type} />
            <Stat label="Subtype" value={listing.commercial.property_subtype} />
            <Stat
              label="Size"
              value={`${listing.commercial.size_square_meters.toLocaleString()} m²`}
            />
            <Stat
              label="Possession period"
              value={`${listing.commercial.possession_period_days} days`}
            />
          </div>

          {listing.commercial.rooms.length > 0 && (
            <div className="mt-md overflow-x-auto">
              <p className="mb-xs text-xs font-medium uppercase text-text-secondary">Rooms</p>
              <table className="w-full min-w-[320px] border-collapse text-sm">
                <thead>
                  <tr className="border-b border-border text-left text-text-secondary">
                    <th className="py-xs pr-md">Level</th>
                    <th className="py-xs pr-md">Width (m)</th>
                    <th className="py-xs">Length (m)</th>
                  </tr>
                </thead>
                <tbody>
                  {listing.commercial.rooms.map((r, i) => (
                    <tr key={i} className="border-b border-border">
                      <td className="py-xs pr-md">{r.level}</td>
                      <td className="py-xs pr-md">{r.width_meters}</td>
                      <td className="py-xs">{r.length_meters}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          {listing.commercial.legal_documents.length > 0 && (
            <div className="mt-md">
              <p className="text-xs font-medium uppercase text-text-secondary">Legal documents</p>
              <ul className="mt-xs list-inside list-disc text-sm">
                {listing.commercial.legal_documents.map((url) => (
                  <li key={url}>
                    <a href={url} target="_blank" rel="noreferrer" className="underline">
                      {url.split("/").pop() ?? url}
                    </a>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>
      )}

      {listing.shortlet && (
        <div className="rounded-lg border border-border p-lg dark:border-border-dark">
          <h3 className="font-heading text-base font-semibold">Shortlet details</h3>
          <div className="mt-sm grid grid-cols-2 gap-sm text-sm sm:grid-cols-4">
            <Stat label="Bedrooms" value={listing.shortlet.bedrooms} />
            <Stat label="Minimum stay" value={`${listing.shortlet.minimum_stay_nights} nights`} />
            <Stat label="Maximum stay" value={`${listing.shortlet.maximum_stay_nights} nights`} />
            <Stat
              label="Blocked dates"
              value={listing.shortlet.blocked_dates.length}
            />
          </div>
          {listing.shortlet.house_rules && (
            <div className="mt-md">
              <p className="text-xs font-medium uppercase text-text-secondary">House rules</p>
              <p className="mt-xs whitespace-pre-wrap text-sm">{listing.shortlet.house_rules}</p>
            </div>
          )}
          {listing.shortlet.blocked_dates.length > 0 && (
            <div className="mt-md">
              <p className="text-xs font-medium uppercase text-text-secondary">Blocked dates</p>
              <p className="mt-xs text-sm text-text-secondary">
                {listing.shortlet.blocked_dates.join(", ")}
              </p>
            </div>
          )}
        </div>
      )}

      <div>
        <h3 className="font-heading text-base font-semibold">Related activity</h3>
        <div className="mt-sm grid grid-cols-1 gap-md sm:grid-cols-2 lg:grid-cols-4">
          <SummaryCard
            label="Disputes"
            count={disputeCount}
            href={`/disputes?listing_id=${listingId}`}
          />
          <SummaryCard
            label="Moderation queue"
            count={moderationCount}
            href={`/moderation-queue?listing_id=${listingId}`}
          />
          <SummaryCard
            label="Pending release"
            count={pendingReleaseCount}
            href={`/release-funds?listing_id=${listingId}`}
          />
          <SummaryCard
            label="Released"
            count={releasedCount}
            href={`/release-funds?listing_id=${listingId}&status_filter=released`}
          />
          {/* Conversations live in Firestore (ChatOversightClient), not a
              REST-queryable count here -- links straight to Conversations
              pre-filtered by this listing rather than showing a number. */}
          <SummaryCard
            label="Conversations"
            count={null}
            href={`/conversations?listing_id=${listingId}`}
          />
        </div>
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string | number }) {
  return (
    <div>
      <p className="text-xs uppercase text-text-secondary">{label}</p>
      <p className="font-medium">{value}</p>
    </div>
  );
}

function SummaryCard({
  label,
  count,
  href,
}: {
  label: string;
  count: number | null;
  href: string;
}) {
  return (
    <Link
      href={href}
      className="rounded-lg border border-border p-md transition-colors duration-150 ease-out-smooth hover:bg-surface-secondary dark:border-border-dark dark:hover:bg-surface-secondary-dark"
    >
      <p className="text-2xl font-semibold">{count ?? "--"}</p>
      <p className="text-sm text-text-secondary">{label}</p>
      <p className="mt-xs text-xs underline">View all</p>
    </Link>
  );
}
