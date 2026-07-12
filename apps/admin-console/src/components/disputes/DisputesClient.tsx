"use client";

import { useCallback, useEffect, useState } from "react";

import { DisputeDetailPanel } from "./DisputeDetailPanel";
import { REASON_LABELS } from "./types";
import type { DisputeListItem, DisputeStatus } from "./types";

const API_BASE_URL = "/api/backend/v1";

type LoadState = "loading" | "loaded" | "empty" | "error";

const STATUS_FILTERS: { value: DisputeStatus | "all"; label: string }[] = [
  { value: "all", label: "All" },
  { value: "open", label: "Open" },
  { value: "under_review", label: "Under review" },
  { value: "resolved_refunded", label: "Resolved (refunded)" },
  { value: "resolved_no_refund", label: "Resolved (no refund)" },
  { value: "closed", label: "Closed" },
];

async function fetchDisputes(statusFilter: DisputeStatus | "all"): Promise<DisputeListItem[]> {
  const query = statusFilter === "all" ? "" : `?status_filter=${statusFilter}`;
  const response = await fetch(`${API_BASE_URL}/disputes${query}`);
  if (!response.ok) {
    throw new Error(`Failed to load disputes (${response.status})`);
  }
  return response.json();
}

/** screens.md Screen 24: Admin Dispute & Refund Management -- FEAT-026.
 * Table of disputes filterable by status; clicking a row opens the Dispute
 * Detail View (assign + resolve). */
export function DisputesClient() {
  const [state, setState] = useState<LoadState>("loading");
  const [items, setItems] = useState<DisputeListItem[]>([]);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<DisputeStatus | "all">("all");
  const [openDisputeId, setOpenDisputeId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setState("loading");
    try {
      const data = await fetchDisputes(statusFilter);
      setItems(data);
      setState(data.length === 0 ? "empty" : "loaded");
    } catch (e) {
      setErrorMessage(e instanceof Error ? e.message : "Something went wrong.");
      setState("error");
    }
  }, [statusFilter]);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <>
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
        {state === "loading" && <p className="text-text-secondary">Loading disputes...</p>}

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
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="border-b border-border text-left text-text-secondary">
                <th className="py-sm pr-md">Transaction</th>
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
                  className="cursor-pointer border-b border-border hover:bg-surface-secondary dark:hover:bg-surface-dark"
                  onClick={() => setOpenDisputeId(item.id)}
                >
                  <td className="py-sm pr-md font-medium">{item.transaction_id}</td>
                  <td className="py-sm pr-md">{item.raised_by_name}</td>
                  <td className="py-sm pr-md">{REASON_LABELS[item.reason]}</td>
                  <td className="py-sm pr-md capitalize">{item.status.replace(/_/g, " ")}</td>
                  <td className="py-sm pr-md">{item.assigned_staff_name ?? "Unassigned"}</td>
                  <td className="py-sm">{new Date(item.created_at).toLocaleString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
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
