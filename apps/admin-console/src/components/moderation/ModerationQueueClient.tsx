"use client";

import { useCallback, useEffect, useState } from "react";
import { ModerationDecisionDialog } from "./ModerationDecisionDialog";
import type { ModerationAction, ModerationQueueItem } from "./types";

// TODO: centralize once a shared admin-console API client module exists;
// for now this reads the Backend API Service base URL from env, per
// architecture.md ("all /v1 endpoints"), and expects the caller's session
// cookie/bearer token to already be attached by the platform's auth layer
// (see src/lib/auth.ts -- getAdminSession()/requireAdminRole() stubs).
const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "";

type LoadState = "loading" | "loaded" | "empty" | "error";

async function fetchQueue(): Promise<ModerationQueueItem[]> {
  const response = await fetch(`${API_BASE_URL}/v1/moderation/queue`, {
    credentials: "include",
  });
  if (!response.ok) {
    throw new Error(`Failed to load moderation queue (${response.status})`);
  }
  return response.json();
}

async function submitDecision(listingId: string, action: ModerationAction, reason: string) {
  const response = await fetch(`${API_BASE_URL}/v1/moderation/${listingId}/${action}`, {
    method: "POST",
    credentials: "include",
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
    await submitDecision(pendingDecision.item.listing_id, pendingDecision.action, reason);
    setPendingDecision(null);
    await load();
  }

  if (state === "loading") {
    return <p className="text-text-secondary">Loading moderation queue...</p>;
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
            <tr key={item.listing_id} className="border-b border-border">
              <td className="py-sm pr-md font-medium">{item.title}</td>
              <td className="py-sm pr-md capitalize">{item.listing_type}</td>
              <td className="py-sm pr-md capitalize">{item.host_type}</td>
              <td className="py-sm pr-md capitalize">{item.status}</td>
              <td className="py-sm pr-md">{new Date(item.created_at).toLocaleString()}</td>
              <td className="py-sm">
                <div className="flex gap-sm">
                  <button
                    type="button"
                    className="rounded-md bg-primary px-sm py-1 text-white hover:bg-primary-hover"
                    onClick={() => setPendingDecision({ item, action: "approve" })}
                  >
                    Approve
                  </button>
                  <button
                    type="button"
                    className="rounded-md bg-error px-sm py-1 text-white"
                    onClick={() => setPendingDecision({ item, action: "ban" })}
                  >
                    Ban
                  </button>
                </div>
              </td>
            </tr>
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
