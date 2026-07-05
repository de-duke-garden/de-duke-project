"use client";

import { useCallback, useEffect, useState } from "react";

import { EditRateModal } from "./EditRateModal";
import {
  CommissionRateHistoryResponse,
  TRANSACTION_TYPES,
  TRANSACTION_TYPE_LABELS,
} from "./types";

// Proxied through a same-origin Route Handler that attaches the session
// token server-side -- see src/app/api/backend/[...path]/route.ts.
const API_BASE_URL = "/api/backend/v1";

type LoadState = "loading" | "loaded" | "error";

async function fetchRate(transactionType: string): Promise<CommissionRateHistoryResponse> {
  const response = await fetch(API_BASE_URL + "/commission/" + transactionType);
  if (response.ok === false) {
    throw new Error("Failed to load " + transactionType + " rate (" + response.status + ")");
  }
  return response.json();
}

async function saveRate(transactionType: string, ratePercentage: number) {
  const response = await fetch(API_BASE_URL + "/commission", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ transaction_type: transactionType, rate_percentage: ratePercentage }),
  });
  if (response.ok === false) {
    const body = await response.json().catch(() => null);
    throw new Error(body?.detail ?? "Failed to save the new rate (" + response.status + ")");
  }
}

/** screens.md Screen 25: Admin Commission Rate Configuration. Staff see
 * this read-only (no Edit action rendered); Admin can edit. Server-side
 * enforcement is the real gate (POST is require_roles(DEDUKE_ADMIN) only)
 * -- `isAdmin` here is a UX nicety, never the security boundary. */
export function CommissionConfigClient({ isAdmin }: { isAdmin: boolean }) {
  const [state, setState] = useState<LoadState>("loading");
  const [rates, setRates] = useState<Record<string, CommissionRateHistoryResponse>>({});
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [editingType, setEditingType] = useState<string | null>(null);
  const [expandedHistory, setExpandedHistory] = useState<Record<string, boolean>>({});

  const load = useCallback(async () => {
    setState("loading");
    try {
      const results = await Promise.all(TRANSACTION_TYPES.map((t) => fetchRate(t)));
      const byType: Record<string, CommissionRateHistoryResponse> = {};
      results.forEach((r) => {
        byType[r.transaction_type] = r;
      });
      setRates(byType);
      setState("loaded");
    } catch (e) {
      setErrorMessage(e instanceof Error ? e.message : "Something went wrong.");
      setState("error");
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function handleSave(transactionType: string, newRate: number) {
    await saveRate(transactionType, newRate);
    setEditingType(null);
    await load();
  }

  if (state === "loading") {
    return (
      <div className="space-y-sm">
        {TRANSACTION_TYPES.map((t) => (
          <div key={t} className="h-20 animate-pulse rounded-md bg-surface-secondary dark:bg-surface-secondary-dark" />
        ))}
      </div>
    );
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

  return (
    <div className="space-y-md">
      {TRANSACTION_TYPES.map((type) => {
        const data = rates[type];
        const current = data?.current ?? null;
        const history = data?.history ?? [];
        const isExpanded = expandedHistory[type] ?? false;

        return (
          <div key={type} className="rounded-lg border border-border p-md dark:border-border-dark">
            <div className="flex items-center justify-between">
              <div>
                <h3 className="font-heading text-base font-semibold">
                  {TRANSACTION_TYPE_LABELS[type] ?? type}
                </h3>
                <p className="mt-xs text-2xl font-semibold text-primary">
                  {current ? current.rate_percentage + "%" : "Not set"}
                </p>
              </div>
              {isAdmin && (
                <button
                  type="button"
                  className="rounded-md bg-primary px-md py-sm text-sm font-medium text-white hover:bg-primary-hover"
                  onClick={() => setEditingType(type)}
                >
                  Edit
                </button>
              )}
            </div>

            <button
              type="button"
              className="mt-sm text-sm text-text-secondary underline"
              onClick={() =>
                setExpandedHistory((prev) => ({ ...prev, [type]: !prev[type] }))
              }
            >
              {isExpanded ? "Hide history" : "Show history (" + history.length + ")"}
            </button>

            {isExpanded && (
              <table className="mt-sm w-full border-collapse text-sm">
                <thead>
                  <tr className="border-b border-border text-left text-text-secondary">
                    <th className="py-xs pr-md">Rate</th>
                    <th className="py-xs pr-md">Effective from</th>
                    <th className="py-xs">Set by</th>
                  </tr>
                </thead>
                <tbody>
                  {history.map((entry) => (
                    <tr key={entry.id} className="border-b border-border">
                      <td className="py-xs pr-md">{entry.rate_percentage}%</td>
                      <td className="py-xs pr-md">{new Date(entry.effective_from).toLocaleString()}</td>
                      <td className="py-xs">{entry.set_by_id}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        );
      })}

      {editingType && (
        <EditRateModal
          transactionType={editingType}
          currentRate={rates[editingType]?.current?.rate_percentage ?? null}
          onCancel={() => setEditingType(null)}
          onConfirm={(newRate) => handleSave(editingType, newRate)}
        />
      )}
    </div>
  );
}
