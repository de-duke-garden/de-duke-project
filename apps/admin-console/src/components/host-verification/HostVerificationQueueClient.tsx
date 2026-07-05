"use client";

import { useCallback, useEffect, useState } from "react";

import { ReviewDecisionDialog } from "./ReviewDecisionDialog";
import { SubmissionDetailPanel } from "./SubmissionDetailPanel";
import type { HostAccountDetail, HostAccountQueueItem, ReviewDecision } from "./types";

// Proxied through a same-origin Route Handler that attaches the session
// token server-side -- see src/app/api/backend/[...path]/route.ts.
const API_BASE_URL = "/api/backend/v1";

type LoadState = "loading" | "loaded" | "empty" | "error";

async function fetchQueue(hostTypeFilter: string | null): Promise<HostAccountQueueItem[]> {
  const params = new URLSearchParams({ status_filter: "in_review" });
  const response = await fetch(API_BASE_URL + "/host-accounts/admin?" + params.toString());
  if (response.ok === false) {
    throw new Error("Failed to load the verification queue (" + response.status + ")");
  }
  const body = await response.json();
  const items: HostAccountQueueItem[] = body.items ?? [];
  return hostTypeFilter ? items.filter((i) => i.host_type === hostTypeFilter) : items;
}

async function fetchDetail(id: string): Promise<HostAccountDetail> {
  const response = await fetch(API_BASE_URL + "/host-accounts/admin/" + id);
  if (response.ok === false) {
    throw new Error("Failed to load submission detail (" + response.status + ")");
  }
  return response.json();
}

async function submitDecision(id: string, decision: ReviewDecision, reason: string | undefined) {
  const response = await fetch(API_BASE_URL + "/host-accounts/admin/" + id + "/status", {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ decision, reason: reason ?? null }),
  });
  if (response.ok === false) {
    const body = await response.json().catch(() => null);
    // Screen 27 edge case: two staff act on the same submission -- the
    // backend returns 409 with an "already reviewed" message rather than
    // silently overwriting the outcome.
    throw new Error(body?.detail ?? "Failed to submit the decision (" + response.status + ")");
  }
}

const HOST_TYPES = ["owner", "agent", "company", "lawyer", "architect", "surveyor"];

/** screens.md Screen 27: Admin Host Verification Review. */
export function HostVerificationQueueClient() {
  const [state, setState] = useState<LoadState>("loading");
  const [items, setItems] = useState<HostAccountQueueItem[]>([]);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [hostTypeFilter, setHostTypeFilter] = useState<string | null>(null);

  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detail, setDetail] = useState<HostAccountDetail | null>(null);
  const [detailError, setDetailError] = useState<string | null>(null);
  const [pendingDecision, setPendingDecision] = useState<ReviewDecision | null>(null);

  const load = useCallback(async () => {
    setState("loading");
    try {
      const data = await fetchQueue(hostTypeFilter);
      setItems(data);
      setState(data.length === 0 ? "empty" : "loaded");
    } catch (e) {
      setErrorMessage(e instanceof Error ? e.message : "Something went wrong.");
      setState("error");
    }
  }, [hostTypeFilter]);

  useEffect(() => {
    void load();
  }, [load]);

  async function openDetail(id: string) {
    setSelectedId(id);
    setDetail(null);
    setDetailError(null);
    try {
      setDetail(await fetchDetail(id));
    } catch (e) {
      setDetailError(e instanceof Error ? e.message : "Could not load this submission.");
    }
  }

  function closeDetail() {
    setSelectedId(null);
    setDetail(null);
    setDetailError(null);
    setPendingDecision(null);
  }

  async function handleConfirmDecision(reason: string | undefined) {
    if (!selectedId || !pendingDecision) return;
    await submitDecision(selectedId, pendingDecision, reason);
    setPendingDecision(null);
    closeDetail();
    await load();
  }

  return (
    <div>
      <div className="mb-md flex flex-wrap items-center gap-sm">
        <label htmlFor="host-type-filter" className="text-sm font-medium text-text-secondary">
          Filter by host type
        </label>
        <select
          id="host-type-filter"
          className="rounded-md border border-border bg-transparent px-sm py-xs text-sm"
          value={hostTypeFilter ?? ""}
          onChange={(e) => setHostTypeFilter(e.target.value === "" ? null : e.target.value)}
        >
          <option value="">All</option>
          {HOST_TYPES.map((t) => (
            <option key={t} value={t} className="capitalize">
              {t}
            </option>
          ))}
        </select>
      </div>

      {state === "loading" && <p className="text-text-secondary">Loading verification queue...</p>}

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

      {state === "empty" && <p className="text-text-secondary">Queue is clear.</p>}

      {state === "loaded" && (
        <table className="w-full border-collapse text-sm">
          <thead>
            <tr className="border-b border-border text-left text-text-secondary">
              <th className="py-sm pr-md">User</th>
              <th className="py-sm pr-md">Host type</th>
              <th className="py-sm pr-md">Submitted</th>
              <th className="py-sm">Age</th>
            </tr>
          </thead>
          <tbody>
            {items.map((item) => (
              <tr
                key={item.id}
                className="cursor-pointer border-b border-border hover:bg-surface-secondary dark:hover:bg-surface-secondary-dark"
                onClick={() => void openDetail(item.id)}
              >
                <td className="py-sm pr-md font-medium">{item.user_id}</td>
                <td className="py-sm pr-md capitalize">{item.host_type}</td>
                <td className="py-sm pr-md">{new Date(item.created_at).toLocaleString()}</td>
                <td className="py-sm">{ageLabel(item.created_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {selectedId && (
        <div className="fixed inset-0 z-40 flex items-center justify-center bg-black/40 p-md">
          <div className="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-lg bg-surface p-lg shadow-xl dark:bg-surface-secondary-dark">
            <div className="mb-md flex items-center justify-between">
              <h2 className="font-heading text-lg font-semibold">Submission detail</h2>
              <button type="button" onClick={closeDetail} className="text-text-secondary">
                Close
              </button>
            </div>

            {detailError && <p className="text-error">{detailError}</p>}
            {!detailError && !detail && <p className="text-text-secondary">Loading...</p>}
            {detail && (
              <>
                <SubmissionDetailPanel detail={detail} />
                <div className="mt-lg flex justify-end gap-sm">
                  <button
                    type="button"
                    className="rounded-md bg-error px-md py-sm text-sm font-medium text-white"
                    onClick={() => setPendingDecision("rejected")}
                  >
                    Reject
                  </button>
                  <button
                    type="button"
                    className="rounded-md bg-primary px-md py-sm text-sm font-medium text-white hover:bg-primary-hover"
                    onClick={() => setPendingDecision("verified")}
                  >
                    Verify
                  </button>
                </div>
              </>
            )}
          </div>
        </div>
      )}

      {pendingDecision && detail && (
        <ReviewDecisionDialog
          decision={pendingDecision}
          submissionLabel={detail.host_type + " submission -- " + detail.user_id}
          onCancel={() => setPendingDecision(null)}
          onConfirm={handleConfirmDecision}
        />
      )}
    </div>
  );
}

function ageLabel(createdAt: string): string {
  const ms = Date.now() - new Date(createdAt).getTime();
  const hours = Math.floor(ms / (1000 * 60 * 60));
  if (hours < 1) return "< 1 hour";
  if (hours < 24) return hours + (hours === 1 ? " hour" : " hours");
  const days = Math.floor(hours / 24);
  return days + (days === 1 ? " day" : " days");
}
