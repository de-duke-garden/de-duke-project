"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";

import { Modal } from "@/components/ui/Modal";
import { StatusBadge } from "@/components/ui/StatusBadge";
import { TableSkeleton } from "@/components/ui/Skeleton";
import { RELEASE_QUEUE_FILTERS, TRANSACTION_TYPE_LABELS } from "./types";
import type { ReleasableTransaction, ReleaseQueueFilter } from "./types";

// Proxied through a same-origin Route Handler that attaches the session
// token server-side -- see src/app/api/backend/[...path]/route.ts.
const API_BASE_URL = "/api/backend/v1";

type LoadState = "loading" | "loaded" | "empty" | "error";

async function fetchReleasable(
  statusFilter: ReleaseQueueFilter,
  listingId: string | null,
): Promise<ReleasableTransaction[]> {
  const query = new URLSearchParams({ status_filter: statusFilter });
  if (listingId) query.set("listing_id", listingId);
  const response = await fetch(`${API_BASE_URL}/wallet/admin/releasable?${query.toString()}`);
  if (!response.ok) {
    throw new Error(`Failed to load the release queue (${response.status})`);
  }
  return response.json();
}

async function releaseTransaction(transactionId: string) {
  const response = await fetch(
    `${API_BASE_URL}/wallet/admin/${transactionId}/release`,
    { method: "POST" },
  );
  if (!response.ok) {
    const body = await response.json().catch(() => null);
    throw new Error(body?.detail ?? `Failed to release funds (${response.status})`);
  }
}

const EMPTY_MESSAGE: Record<ReleaseQueueFilter, string> = {
  pending:
    "Nothing waiting on release -- every paid transaction has already been released to its payee's wallet.",
  released: "No transactions have been released yet.",
  all: "No paid transactions yet.",
};

/** FEAT-043's Release Funds screen -- every transaction that has actually
 * been paid, filterable by whether it's still escrowed ('pending', the
 * to-do queue) or already released ('released', a persisted log of
 * completed releases -- a row is never removed from this screen once
 * acted on, it just moves filters). Admin-only per the backend's own
 * require_roles(DEDUKE_ADMIN) gate on both GET and POST here.
 *
 * Global cross-property screen by design (an Admin works a payout backlog
 * oldest-first, not property by property) -- each row's Property link goes
 * to `/properties/:id` for drill-down context, without this global view
 * going away; `?listing_id=`/`?status_filter=` in the URL (set by that
 * page's "Pending release"/"Released" summary cards) pre-filter this table
 * to just that property, read once on mount.
 *
 * FEAT-043/FEAT-026 coupling: a pending row with an open dispute against
 * it shows a warning badge (linking to Disputes, pre-filtered to that
 * property) and its Release action is disabled -- money-safety reasoning:
 * once released, a transaction can't be refunded through the normal
 * dispute-resolution path, so releasing while a dispute is under active
 * investigation would make that dispute much harder to resolve fairly.
 * This is a surfaced warning only, never a re-implementation of the
 * Disputes screen -- the real enforcement is a hard block server-side in
 * wallet_service.release_transaction.
 */
export function ReleaseFundsClient() {
  const searchParams = useSearchParams();
  const listingIdFilter = searchParams.get("listing_id");
  // Deep-linked from the property detail page's "Released" summary card
  // (?status_filter=released) as well as its "Pending release" card
  // (no status_filter -- defaults to "pending"); read once on mount.
  const initialStatusFilter =
    (searchParams.get("status_filter") as ReleaseQueueFilter | null) ?? "pending";

  const [statusFilter, setStatusFilter] = useState<ReleaseQueueFilter>(initialStatusFilter);
  const [state, setState] = useState<LoadState>("loading");
  const [items, setItems] = useState<ReleasableTransaction[]>([]);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [pendingRelease, setPendingRelease] = useState<ReleasableTransaction | null>(null);
  const [releasing, setReleasing] = useState(false);
  const [releaseError, setReleaseError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setState("loading");
    try {
      const data = await fetchReleasable(statusFilter, listingIdFilter);
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

  async function handleConfirmRelease() {
    if (!pendingRelease) return;
    setReleasing(true);
    setReleaseError(null);
    try {
      await releaseTransaction(pendingRelease.transaction_id);
      setPendingRelease(null);
      await load();
    } catch (e) {
      setReleaseError(e instanceof Error ? e.message : "Something went wrong.");
    } finally {
      setReleasing(false);
    }
  }

  return (
    <>
      {listingIdFilter && (
        <div className="mb-md rounded-md border border-primary bg-primary/5 p-sm text-sm">
          Showing release history for property {listingIdFilter}.{" "}
          <Link href="/release-funds" className="underline">
            Clear filter
          </Link>
        </div>
      )}

      <div className="flex flex-wrap gap-sm">
        {RELEASE_QUEUE_FILTERS.map((f) => (
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
          <p className="text-text-secondary">{EMPTY_MESSAGE[statusFilter]}</p>
        )}

        {state === "loaded" && (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[900px] border-collapse text-sm">
              <thead>
                <tr className="border-b border-border text-left text-text-secondary">
                  <th className="py-sm pr-md">Transaction</th>
                  <th className="py-sm pr-md">Listing</th>
                  <th className="py-sm pr-md">Type</th>
                  <th className="py-sm pr-md">Gross</th>
                  <th className="py-sm pr-md">Commission</th>
                  <th className="py-sm pr-md">Net payout</th>
                  <th className="py-sm pr-md">Status</th>
                  <th className="py-sm" />
                </tr>
              </thead>
              <tbody>
                {items.map((item) => {
                  const isReleased = item.status === "released_to_wallet";
                  return (
                    <tr key={item.transaction_id} className="border-b border-border">
                      <td className="py-sm pr-md font-medium">{item.transaction_id}</td>
                      <td className="py-sm pr-md">
                        <Link
                          href={`/properties/${item.listing_id}`}
                          className="underline"
                        >
                          View property
                        </Link>
                      </td>
                      <td className="py-sm pr-md">
                        {TRANSACTION_TYPE_LABELS[item.transaction_type] ?? item.transaction_type}
                      </td>
                      <td className="py-sm pr-md">&#8358;{item.gross_amount.toLocaleString()}</td>
                      <td className="py-sm pr-md">
                        &#8358;{item.commission_amount.toLocaleString()}
                      </td>
                      <td className="py-sm pr-md font-medium">
                        &#8358;{item.net_payout_amount.toLocaleString()}
                      </td>
                      <td className="py-sm pr-md">
                        <StatusBadge
                          value={item.status}
                          label={isReleased ? "Released" : "Pending release"}
                          tone={isReleased ? "success" : "warning"}
                        />
                        <p className="mt-xs text-xs text-text-secondary">
                          {isReleased
                            ? item.released_at
                              ? `Released ${new Date(item.released_at).toLocaleString()}`
                              : "Released"
                            : item.paid_at
                              ? `Paid ${new Date(item.paid_at).toLocaleString()}`
                              : null}
                        </p>
                        {/* FEAT-043/FEAT-026 coupling -- surfaced here
                            (warning + link out), never re-implemented:
                            the actual enforcement is a hard block in
                            wallet_service.release_transaction regardless
                            of this badge. */}
                        {item.has_open_dispute && (
                          <Link
                            href={`/disputes?listing_id=${item.listing_id}`}
                            className="mt-xs inline-flex items-center gap-1 rounded-full bg-error/10 px-sm py-0.5 text-xs font-medium text-error"
                          >
                            {"\u{1F6A9}"} Open dispute
                          </Link>
                        )}
                      </td>
                      <td className="py-sm">
                        {!isReleased &&
                          (item.has_open_dispute ? (
                            <span
                              className="text-xs text-text-secondary"
                              title="Resolve the open dispute on this transaction before releasing funds."
                            >
                              Blocked -- open dispute
                            </span>
                          ) : (
                            <button
                              type="button"
                              className="rounded-md bg-primary px-md py-sm text-sm font-medium text-white hover:bg-primary-hover"
                              onClick={() => setPendingRelease(item)}
                            >
                              Release
                            </button>
                          ))}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {pendingRelease && (
        <Modal
          size="sm"
          labelledBy="release-funds-heading"
          onClose={() => {
            if (!releasing) {
              setPendingRelease(null);
              setReleaseError(null);
            }
          }}
        >
          <h2 id="release-funds-heading" className="font-heading text-lg font-semibold">
            Release funds
          </h2>
          <p className="mt-sm text-sm text-text-secondary">
            This will credit &#8358;{pendingRelease.net_payout_amount.toLocaleString()} to the
            payee&apos;s Wallet for transaction {pendingRelease.transaction_id}. This action cannot
            be undone -- confirm the necessary handover has actually taken place before
            releasing.
          </p>
          {releaseError && <p className="mt-xs text-sm text-error">{releaseError}</p>}
          <div className="mt-lg flex justify-end gap-sm">
            <button
              type="button"
              className="rounded-md border border-border px-md py-sm text-sm"
              onClick={() => {
                setPendingRelease(null);
                setReleaseError(null);
              }}
              disabled={releasing}
            >
              Cancel
            </button>
            <button
              type="button"
              className="rounded-md bg-primary px-md py-sm text-sm font-medium text-white hover:bg-primary-hover"
              onClick={() => void handleConfirmRelease()}
              disabled={releasing}
            >
              {releasing ? "Releasing..." : "Confirm release"}
            </button>
          </div>
        </Modal>
      )}
    </>
  );
}
