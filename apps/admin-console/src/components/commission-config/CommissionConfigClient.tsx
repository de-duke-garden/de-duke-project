"use client";

import { useCallback, useEffect, useRef, useState } from "react";

import { CardGridSkeleton } from "@/components/ui/Skeleton";
import { EditRateModal } from "./EditRateModal";
import {
  FEE_TYPES,
  FEE_TYPE_LABELS,
  TRANSACTION_TYPES,
  TRANSACTION_TYPE_LABELS,
} from "./types";
import type { CommissionRateHistoryResponse, FeeType } from "./types";

// Proxied through a same-origin Route Handler that attaches the session
// token server-side -- see src/app/api/backend/[...path]/route.ts.
const API_BASE_URL = "/api/backend/v1";

type LoadState = "loading" | "loaded" | "error";

// Keys a (transaction_type, fee_type) pair into one string -- both maps
// below (`rates`, `expandedHistory`) are keyed this way since every rate
// card is now scoped to one specific pair, not just a transaction_type.
function pairKey(transactionType: string, feeType: FeeType): string {
  return `${transactionType}:${feeType}`;
}

async function fetchRate(
  transactionType: string,
  feeType: FeeType,
): Promise<CommissionRateHistoryResponse> {
  const response = await fetch(API_BASE_URL + "/commission/" + transactionType + "/" + feeType);
  if (response.ok === false) {
    throw new Error(
      "Failed to load " + transactionType + "/" + feeType + " rate (" + response.status + ")",
    );
  }
  return response.json();
}

async function saveRate(transactionType: string, feeType: FeeType, ratePercentage: number) {
  const response = await fetch(API_BASE_URL + "/commission", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      transaction_type: transactionType,
      fee_type: feeType,
      rate_percentage: ratePercentage,
    }),
  });
  if (response.ok === false) {
    const body = await response.json().catch(() => null);
    throw new Error(
      body?.detail ?? "Failed to save the new rate (" + response.status + ")",
    );
  }
}

/** screens.md Screen 25: Admin Commission Rate Configuration. Staff see
 * this read-only (no Edit action rendered); Admin can edit. Server-side
 * enforcement is the real gate (POST is require_roles(DEDUKE_ADMIN) only)
 * -- `isAdmin` here is a UX nicety, never the security boundary.
 *
 * Two-sided commission model (product decision): each transaction type
 * shows TWO independent rates -- Buyer fee (added to the listing price
 * the guest pays) and Owner commission (deducted from the payee's net
 * payout) -- each with its own edit action and history, not one rate
 * split two ways. See types.ts's own docstring.
 */
export function CommissionConfigClient({ isAdmin }: { isAdmin: boolean }) {
  const [state, setState] = useState<LoadState>("loading");
  const [rates, setRates] = useState<
    Record<string, CommissionRateHistoryResponse>
  >({});
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [editing, setEditing] = useState<{ transactionType: string; feeType: FeeType } | null>(
    null,
  );
  const [expandedHistory, setExpandedHistory] = useState<
    Record<string, boolean>
  >({});

  const load = useCallback(async () => {
    setState("loading");
    try {
      const pairs = TRANSACTION_TYPES.flatMap((t) => FEE_TYPES.map((f) => [t, f] as const));
      const results = await Promise.all(pairs.map(([t, f]) => fetchRate(t, f)));
      const byPair: Record<string, CommissionRateHistoryResponse> = {};
      results.forEach((r) => {
        byPair[pairKey(r.transaction_type, r.fee_type)] = r;
      });
      setRates(byPair);
      setState("loaded");
    } catch (e) {
      setErrorMessage(e instanceof Error ? e.message : "Something went wrong.");
      setState("error");
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  async function handleSave(transactionType: string, feeType: FeeType, newRate: number) {
    await saveRate(transactionType, feeType, newRate);
    setEditing(null);
    await load();
  }

  if (state === "loading") {
    return <CardGridSkeleton count={TRANSACTION_TYPES.length * FEE_TYPES.length} />;
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
    <div className="space-y-lg">
      {TRANSACTION_TYPES.map((type) => (
        <div key={type}>
          <h3 className="font-heading text-base font-semibold">
            {TRANSACTION_TYPE_LABELS[type] ?? type}
          </h3>
          <div className="mt-sm grid grid-cols-1 gap-md sm:grid-cols-2">
            {FEE_TYPES.map((feeType) => {
              const key = pairKey(type, feeType);
              const data = rates[key];
              const current = data?.current ?? null;
              const history = data?.history ?? [];
              const isExpanded = expandedHistory[key] ?? false;

              return (
                <div
                  key={feeType}
                  className="rounded-lg border border-border p-md dark:border-border-dark"
                >
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-text-secondary">
                        {FEE_TYPE_LABELS[feeType]}
                      </p>
                      <RateFigure
                        value={current ? current.rate_percentage + "%" : "Not set"}
                      />
                    </div>
                    {isAdmin && (
                      <button
                        type="button"
                        className="rounded-md bg-primary px-md py-sm text-sm font-medium text-white hover:bg-primary-hover"
                        onClick={() => setEditing({ transactionType: type, feeType })}
                      >
                        Edit
                      </button>
                    )}
                  </div>

                  <button
                    type="button"
                    className="mt-sm text-sm text-text-secondary underline"
                    onClick={() =>
                      setExpandedHistory((prev) => ({ ...prev, [key]: !prev[key] }))
                    }
                  >
                    {isExpanded
                      ? "Hide history"
                      : "Show history (" + history.length + ")"}
                  </button>

                  {/* branding.md Screen 25 Modernization Notes: the history
                      Accordion expands with a smooth height transition
                      (`duration-normal`) instead of appearing instantly -- a
                      grid-template-rows 0fr/1fr transition on an always-mounted
                      row achieves that without measuring pixel heights. */}
                  <div
                    className={`grid overflow-hidden transition-[grid-template-rows] duration-200 ease-out-smooth ${
                      isExpanded ? "grid-rows-[1fr] mt-sm" : "grid-rows-[0fr]"
                    }`}
                  >
                    <div className="min-h-0 overflow-x-auto">
                      <table className="w-full min-w-[320px] border-collapse text-sm">
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
                              <td className="py-xs pr-md">
                                {entry.rate_percentage}%
                              </td>
                              <td className="py-xs pr-md">
                                {new Date(entry.effective_from).toLocaleString()}
                              </td>
                              <td className="py-xs">{entry.set_by_id}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      ))}

      {editing && (
        <EditRateModal
          transactionType={editing.transactionType}
          feeType={editing.feeType}
          currentRate={
            rates[pairKey(editing.transactionType, editing.feeType)]?.current?.rate_percentage ??
            null
          }
          onCancel={() => setEditing(null)}
          onConfirm={(newRate) => handleSave(editing.transactionType, editing.feeType, newRate)}
        />
      )}
    </div>
  );
}

/** branding.md Screen 25 Modernization Notes: a successful rate update
 * animates the new value in with `status-badge-pop` on the rate figure
 * itself. Reuses the `animate-badge-pop` keyframe registered in
 * tailwind.config.ts (same one StatusBadge uses) rather than inventing a
 * new one. */
function RateFigure({ value }: { value: string }) {
  const previousValue = useRef(value);
  const [popping, setPopping] = useState(false);

  useEffect(() => {
    if (previousValue.current !== value) {
      previousValue.current = value;
      setPopping(true);
      const timeout = setTimeout(() => setPopping(false), 260);
      return () => clearTimeout(timeout);
    }
  }, [value]);

  return (
    <p
      className={`mt-xs text-2xl font-semibold text-primary ${popping ? "animate-badge-pop" : ""}`}
    >
      {value}
    </p>
  );
}
