"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";

import { TableSkeleton } from "@/components/ui/Skeleton";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { DisputeDetailPanel } from "./DisputeDetailPanel";
import { REASON_LABELS } from "./types";
import type { DisputeListItem, DisputeStatus } from "./types";

const API_BASE_URL = "/api/backend/v1";

type LoadState = "loading" | "loaded" | "empty" | "error";

/** branding.md `status-badge-pop`: tone per dispute status so the pill
 * reads at a glance and pops when it changes. */
const STATUS_TONE: Record<
  DisputeStatus,
  "info" | "warning" | "success" | "neutral"
> = {
  open: "info",
  under_review: "warning",
  resolved_refunded: "success",
  resolved_no_refund: "neutral",
  closed: "neutral",
};

const STATUS_FILTERS: { value: DisputeStatus | "all"; label: string }[] = [
  { value: "all", label: "All" },
  { value: "open", label: "Open" },
  { value: "under_review", label: "Under review" },
  { value: "resolved_refunded", label: "Resolved (refunded)" },
  { value: "resolved_no_refund", label: "Resolved (no refund)" },
  { value: "closed", label: "Closed" },
];

async function fetchDisputes(
  statusFilter: DisputeStatus | "all",
  listingId: string | null,
): Promise<DisputeListItem[]> {
  const query = new URLSearchParams();
  if (statusFilter !== "all") query.set("status_filter", statusFilter);
  if (listingId) query.set("listing_id", listingId);
  const qs = query.toString();
  const response = await fetch(`${API_BASE_URL}/disputes${qs ? `?${qs}` : ""}`);
  if (!response.ok) {
    throw new Error(`Failed to load disputes (${response.status})`);
  }
  return response.json();
}

/** screens.md Screen 24: Admin Dispute & Refund Management -- FEAT-026.
 * Table of disputes filterable by status; clicking a row opens the Dispute
 * Detail View (assign + resolve).
 *
 * `?listing_id=` in the URL (set by the property detail page's "Disputes"
 * summary card link) pre-filters this table to just that property's
 * disputes -- read once on mount, same deep-link convention as the other
 * queue screens (Moderation Queue, Release Funds). */
export function DisputesClient() {
  const searchParams = useSearchParams();
  const listingIdFilter = searchParams.get("listing_id");

  const [state, setState] = useState<LoadState>("loading");
  const [items, setItems] = useState<DisputeListItem[]>([]);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<DisputeStatus | "all">(
    "all",
  );
  const [openDisputeId, setOpenDisputeId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setState("loading");
    try {
      const data = await fetchDisputes(statusFilter, listingIdFilter);
      setItems(data);
      setState(data.length === 0 ? "empty" : "loaded");
    } catch (e) {
      setErrorMessage(e instanceof Error ? e.message : "Something went wrong.");
      setState("error");
    }
  }, [statusFilter, listingIdFilter]);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <>
      {listingIdFilter && (
        <div className="mb-md rounded-md border border-primary bg-primary/5 p-sm text-sm">
          Showing disputes for property {listingIdFilter}.{" "}
          <Link href="/disputes" className="underline">
            Clear filter
          </Link>
        </div>
      )}

      <div className="flex flex-wrap gap-sm">
        {STATUS_FILTERS.map((f) => (
          <button
            key={f.value}
            type="button"
            className={`rounded-full border px-md py-1 text-sm ${
              statusFilter === f.value
                ? "border-primary bg-primary text-white"
                : "border-border text-text-secondary"
            }`}
            onClick={() => setStatusFilter(f.value)}
          >
            {f.label}
          </button>
        ))}
      </div>

      <div className="mt-md">
        {state === "loading" && <TableSkeleton rows={6} columns={7} />}

        {state === "error" && (
          <div className="rounded-md border border-error p-md">
            <p className="text-error">{errorMessage}</p>
            <button
              type="button"
              className="mt-sm rounded-md border border-border px-md py-sm text-sm"
              onClick={() => void load()}
            >
              Retry
            </button>
          </div>
        )}

        {state === "empty" && (
          <p className="text-text-secondary">No disputes to review.</p>
        )}

        {state === "loaded" && (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[720px] border-collapse text-sm">
              <thead>
                <tr className="border-b border-border text-left text-text-secondary">
                  <th className="py-sm pr-md">Transaction</th>
                  <th className="py-sm pr-md">Property</th>
                  <th className="py-sm pr-md">Raised by</th>
                  <th className="py-sm pr-md">Reason</th>
                  <th className="py-sm pr-md">Status</th>
                  <th className="py-sm pr-md">Assigned</th>
                  <th className="py-sm">Raised</th>
                </tr>
              </thead>
              <tbody>
                {items.map((item) => (
                  <tr
                    key={item.id}
                    className="cursor-pointer border-b border-border transition-colors duration-[120ms] ease-out-smooth hover:bg-surface-secondary dark:hover:bg-surface-secondary-dark"
                    onClick={() => setOpenDisputeId(item.id)}
                  >
                    <td className="py-sm pr-md font-medium">
                      {item.transaction_id}
                    </td>
                    <td className="py-sm pr-md">
                      {item.listing_id ? (
                        <Link
                          href={`/properties/${item.listing_id}`}
                          className="underline"
                          onClick={(e) => e.stopPropagation()}
                        >
                          View property
                        </Link>
                      ) : (
                        "--"
                      )}
                    </td>
                    <td className="py-sm pr-md">{item.raised_by_name}</td>
                    <td className="py-sm pr-md">
                      {REASON_LABELS[item.reason]}
                    </td>
                    <td className="py-sm pr-md">
                      <StatusBadge
                        value={item.status}
                        label={item.status.replace(/_/g, " ")}
                        tone={STATUS_TONE[item.status]}
                      />
                    </td>
                    <td className="py-sm pr-md">
                      {item.assigned_staff_name ?? "Unassigned"}
                    </td>
                    <td className="py-sm">
                      {new Date(item.created_at).toLocaleString()}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {openDisputeId && (
        <DisputeDetailPanel
          disputeId={openDisputeId}
          onClose={() => setOpenDisputeId(null)}
          onChanged={() => void load()}
        />
      )}
    </>
  );
}
