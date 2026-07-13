"use client";

import { useCallback, useEffect, useState } from "react";
import { ModerationDecisionDialog } from "./ModerationDecisionDialog";
import { TableSkeleton } from "@/components/ui/Skeleton";
import { ResolvingRow } from "@/components/ui/ResolvingRow";
import type { ModerationAction, ModerationQueueItem } from "./types";

// Proxied through a same-origin Route Handler that attaches the session
// token server-side -- see src/app/api/backend/[...path]/route.ts.
const API_BASE_URL = "/api/backend/v1";

type LoadState = "loading" | "loaded" | "empty" | "error";

async function fetchQueue(): Promise<ModerationQueueItem[]> {
  const response = await fetch(`${API_BASE_URL}/moderation/queue`);
  if (!response.ok) {
    throw new Error(`Failed to load moderation queue (${response.status})`);
  }
  return response.json();
}

async function submitDecision(listingId: string, action: ModerationAction, reason: string) {
  const response = await fetch(`${API_BASE_URL}/moderation/${listingId}/${action}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ reason }),
  });
  if (!response.ok) {
    const body = await response.json().catch(() => null);
    throw new Error(body?.detail ?? `Failed to ${action} listing (${response.status})`);
  }
}

/** screens.md Screen 23: Admin Moderation Queue. Prioritizes oldest
 * under_review/flagged listings first (see moderation_service.py), and
 * requires a reason for every approve/ban decision. */
export function ModerationQueueClient() {
  const [state, setState] = useState<LoadState>("loading");
  const [items, setItems] = useState<ModerationQueueItem[]>([]);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [pendingDecision, setPendingDecision] = useState<{
    item: ModerationQueueItem;
    action: ModerationAction;
  } | null>(null);
  const [resolvingId, setResolvingId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setState("loading");
    try {
      const data = await fetchQueue();
      setItems(data);
      setState(data.length === 0 ? "empty" : "loaded");
    } catch (e) {
      setErrorMessage(e instanceof Error ? e.message : "Something went wrong.");
      setState("error");
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function handleConfirm(reason: string) {
    if (!pendingDecision) return;
    const listingId = pendingDecision.item.listing_id;
    await submitDecision(listingId, pendingDecision.action, reason);
    setPendingDecision(null);
    // `row-resolve` (branding.md Admin Web Console motion system /
    // screens.md Screen 23 Modernization Notes): let the row fade + collapse
    // out of the queue instead of an immediate full-table refresh flash.
    // The item is only removed from `items` once ResolvingRow's
    // `onResolved` fires, below.
    setResolvingId(listingId);
  }

  function handleRowResolved(listingId: string) {
    setItems((prev) => {
      const next = prev.filter((i) => i.listing_id !== listingId);
      if (next.length === 0) setState("empty");
      return next;
    });
    setResolvingId(null);
  }

  if (state === "loading") {
    return <TableSkeleton rows={6} columns={6} />;
  }

  if (state === "error") {
    return (
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
    );
  }

  if (state === "empty") {
    return <p className="text-text-secondary">Nothing waiting for review. Queue is clear.</p>;
  }

  return (
    <>
      <table className="w-full border-collapse text-sm">
        <thead>
          <tr className="border-b border-border text-left text-text-secondary">
            <th className="py-sm pr-md">Listing</th>
            <th className="py-sm pr-md">Type</th>
            <th className="py-sm pr-md">Host type</th>
            <th className="py-sm pr-md">Status</th>
            <th className="py-sm pr-md">Submitted</th>
            <th className="py-sm">Actions</th>
          </tr>
        </thead>
        <tbody>
          {items.map((item) => (
            <ResolvingRow
              key={item.listing_id}
              resolving={item.listing_id === resolvingId}
              onResolved={() => handleRowResolved(item.listing_id)}
              className="border-b border-border transition-colors duration-[120ms] ease-out-smooth hover:bg-surface-secondary dark:border-border-dark dark:hover:bg-surface-secondary-dark"
            >
              <td className="py-sm pr-md font-medium">{item.title}</td>
              <td className="py-sm pr-md capitalize">{item.listing_type}</td>
              <td className="py-sm pr-md capitalize">{item.host_type}</td>
              <td className="py-sm pr-md capitalize">{item.status}</td>
              <td className="py-sm pr-md">{new Date(item.created_at).toLocaleString()}</td>
              <td className="py-sm">
                <div className="flex gap-sm">
                  <button
                    type="button"
                    className="rounded-md bg-primary px-sm py-1 text-white hover:bg-primary-hover disabled:opacity-60"
                    disabled={item.listing_id === resolvingId}
                    onClick={() => setPendingDecision({ item, action: "approve" })}
                  >
                    Approve
                  </button>
                  <button
                    type="button"
                    className="rounded-md bg-error px-sm py-1 text-white disabled:opacity-60"
                    disabled={item.listing_id === resolvingId}
                    onClick={() => setPendingDecision({ item, action: "ban" })}
                  >
                    Ban
                  </button>
                </div>
              </td>
            </ResolvingRow>
          ))}
        </tbody>
      </table>

      {pendingDecision && (
        <ModerationDecisionDialog
          action={pendingDecision.action}
          listingTitle={pendingDecision.item.title}
          onCancel={() => setPendingDecision(null)}
          onConfirm={handleConfirm}
        />
      )}
    </>
  );
}
