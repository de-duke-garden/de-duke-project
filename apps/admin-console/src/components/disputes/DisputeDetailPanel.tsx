"use client";

import { useEffect, useState } from "react";

import type { StaffAccount } from "../staff-management/types";
import { REASON_LABELS } from "./types";
import type { DisputeDetail, DisputeResolution } from "./types";

const API_BASE_URL = "/api/backend/v1";

interface Props {
  disputeId: string;
  onClose: () => void;
  onChanged: () => void;
}

async function fetchDetail(id: string): Promise<DisputeDetail> {
  const response = await fetch(`${API_BASE_URL}/disputes/${id}`);
  if (!response.ok) throw new Error(`Failed to load dispute (${response.status})`);
  return response.json();
}

async function fetchStaff(): Promise<StaffAccount[]> {
  const response = await fetch(`${API_BASE_URL}/staff-accounts`);
  if (!response.ok) throw new Error(`Failed to load staff accounts (${response.status})`);
  return response.json();
}

async function assignDispute(id: string, staffId: string) {
  const response = await fetch(`${API_BASE_URL}/disputes/${id}/assign`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ staff_id: staffId }),
  });
  if (!response.ok) {
    const body = await response.json().catch(() => null);
    throw new Error(body?.detail ?? `Failed to assign dispute (${response.status})`);
  }
}

async function resolveDispute(
  id: string,
  resolution: DisputeResolution,
  resolutionNotes: string,
  refundAmount: number | null,
) {
  const response = await fetch(`${API_BASE_URL}/disputes/${id}/resolve`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      resolution,
      resolution_notes: resolutionNotes,
      refund_amount: refundAmount,
    }),
  });
  if (!response.ok) {
    const body = await response.json().catch(() => null);
    throw new Error(body?.detail ?? `Failed to resolve dispute (${response.status})`);
  }
}

/** screens.md Screen 24's Dispute Detail View: full transaction context,
 * the dispute description, an assignment control, resolution notes field,
 * and "Resolve with Refund" / "Resolve without Refund" actions. */
export function DisputeDetailPanel({ disputeId, onClose, onChanged }: Props) {
  const [detail, setDetail] = useState<DisputeDetail | null>(null);
  const [staff, setStaff] = useState<StaffAccount[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);

  const [selectedStaffId, setSelectedStaffId] = useState("");
  const [assigning, setAssigning] = useState(false);
  const [assignError, setAssignError] = useState<string | null>(null);

  const [pendingResolution, setPendingResolution] = useState<DisputeResolution | null>(null);
  const [resolutionNotes, setResolutionNotes] = useState("");
  const [refundAmount, setRefundAmount] = useState("");
  const [resolving, setResolving] = useState(false);
  const [resolveError, setResolveError] = useState<string | null>(null);

  async function load() {
    try {
      const [detailData, staffData] = await Promise.all([
        fetchDetail(disputeId),
        fetchStaff(),
      ]);
      setDetail(detailData);
      setStaff(staffData);
      setSelectedStaffId(detailData.assigned_staff_id ?? "");
      setLoadError(null);
    } catch (e) {
      setLoadError(e instanceof Error ? e.message : "Something went wrong.");
    }
  }

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [disputeId]);

  async function handleAssign() {
    if (!selectedStaffId) return;
    setAssigning(true);
    setAssignError(null);
    try {
      await assignDispute(disputeId, selectedStaffId);
      await load();
      onChanged();
    } catch (e) {
      setAssignError(e instanceof Error ? e.message : "Something went wrong.");
    } finally {
      setAssigning(false);
    }
  }

  async function handleResolve() {
    if (!pendingResolution) return;
    if (resolutionNotes.trim().length === 0) {
      setResolveError("Resolution notes are required.");
      return;
    }
    const parsedAmount =
      pendingResolution === "resolved_refunded" ? Number(refundAmount) : null;
    if (pendingResolution === "resolved_refunded" && (!parsedAmount || parsedAmount <= 0)) {
      setResolveError("Enter a valid refund amount.");
      return;
    }

    setResolving(true);
    setResolveError(null);
    try {
      await resolveDispute(disputeId, pendingResolution, resolutionNotes.trim(), parsedAmount);
      setPendingResolution(null);
      await load();
      onChanged();
    } catch (e) {
      setResolveError(e instanceof Error ? e.message : "Something went wrong.");
    } finally {
      setResolving(false);
    }
  }

  const isResolved = detail?.status === "resolved_refunded" || detail?.status === "resolved_no_refund";

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-md">
      <div className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-lg bg-surface p-lg shadow-xl dark:bg-surface-secondary-dark">
        <div className="flex items-center justify-between">
          <h2 className="font-heading text-lg font-semibold">Dispute detail</h2>
          <button type="button" className="text-sm text-text-secondary" onClick={onClose}>
            Close
          </button>
        </div>

        {loadError && <p className="mt-md text-sm text-error">{loadError}</p>}

        {!detail && !loadError && (
          <p className="mt-md text-text-secondary">Loading...</p>
        )}

        {detail && (
          <div className="mt-md space-y-md text-sm">
            <div>
              <p className="font-medium">Transaction</p>
              <p className="text-text-secondary">
                {detail.transaction_id} &middot; Listing {detail.listing_id} &middot; &#8358;
                {detail.transaction_gross_amount.toLocaleString()} &middot; {detail.transaction_status}
              </p>
            </div>
            <div>
              <p className="font-medium">Raised by</p>
              <p className="text-text-secondary">{detail.raised_by_name}</p>
            </div>
            <div>
              <p className="font-medium">Reason</p>
              <p className="text-text-secondary">{REASON_LABELS[detail.reason]}</p>
            </div>
            <div>
              <p className="font-medium">Description</p>
              <p className="whitespace-pre-wrap text-text-secondary">{detail.description}</p>
            </div>
            <div>
              <p className="font-medium">Status</p>
              <p className="capitalize text-text-secondary">{detail.status.replace(/_/g, " ")}</p>
            </div>

            {isResolved ? (
              <div className="rounded-md border border-border p-md">
                <p className="font-medium">Resolution</p>
                <p className="text-text-secondary">
                  {detail.status === "resolved_refunded"
                    ? `Refunded ₦${detail.refund_amount?.toLocaleString()}`
                    : "Resolved without refund"}
                </p>
                {detail.resolution_notes && (
                  <p className="mt-xs whitespace-pre-wrap text-text-secondary">
                    {detail.resolution_notes}
                  </p>
                )}
                {detail.resolved_at && (
                  <p className="mt-xs text-xs text-text-secondary">
                    {new Date(detail.resolved_at).toLocaleString()}
                  </p>
                )}
              </div>
            ) : (
              <>
                <div>
                  <label className="block font-medium" htmlFor="assign-staff">
                    Assign to
                  </label>
                  <div className="mt-xs flex gap-sm">
                    <select
                      id="assign-staff"
                      className="w-full rounded-md border border-border bg-transparent p-sm text-sm"
                      value={selectedStaffId}
                      onChange={(e) => setSelectedStaffId(e.target.value)}
                      disabled={assigning}
                    >
                      <option value="">Unassigned</option>
                      {staff.map((s) => (
                        <option key={s.id} value={s.id}>
                          {s.full_name}
                        </option>
                      ))}
                    </select>
                    <button
                      type="button"
                      className="rounded-md border border-border px-md py-sm text-sm"
                      onClick={() => void handleAssign()}
                      disabled={assigning || !selectedStaffId}
                    >
                      {assigning ? "Assigning..." : "Assign"}
                    </button>
                  </div>
                  {assignError && <p className="mt-xs text-sm text-error">{assignError}</p>}
                </div>

                {!pendingResolution ? (
                  <div className="flex gap-sm">
                    <button
                      type="button"
                      className="rounded-md bg-primary px-md py-sm text-sm font-medium text-white hover:bg-primary-hover"
                      onClick={() => setPendingResolution("resolved_refunded")}
                    >
                      Resolve with Refund
                    </button>
                    <button
                      type="button"
                      className="rounded-md border border-border px-md py-sm text-sm font-medium"
                      onClick={() => setPendingResolution("resolved_no_refund")}
                    >
                      Resolve without Refund
                    </button>
                  </div>
                ) : (
                  <div className="rounded-md border border-border p-md">
                    <p className="font-medium">
                      {pendingResolution === "resolved_refunded"
                        ? "Resolve with refund"
                        : "Resolve without refund"}
                    </p>
                    {pendingResolution === "resolved_refunded" && (
                      <>
                        <label className="mt-sm block text-sm" htmlFor="refund-amount">
                          Refund amount (&#8358;)
                        </label>
                        <input
                          id="refund-amount"
                          type="number"
                          min="1"
                          max={detail.transaction_gross_amount}
                          className="mt-xs w-full rounded-md border border-border bg-transparent p-sm text-sm"
                          value={refundAmount}
                          onChange={(e) => setRefundAmount(e.target.value)}
                          disabled={resolving}
                        />
                      </>
                    )}
                    <label className="mt-sm block text-sm" htmlFor="resolution-notes">
                      Resolution notes
                    </label>
                    <textarea
                      id="resolution-notes"
                      rows={3}
                      className="mt-xs w-full rounded-md border border-border bg-transparent p-sm text-sm"
                      value={resolutionNotes}
                      onChange={(e) => setResolutionNotes(e.target.value)}
                      disabled={resolving}
                    />
                    {resolveError && (
                      <p className="mt-xs text-sm text-error">{resolveError}</p>
                    )}
                    <div className="mt-sm flex justify-end gap-sm">
                      <button
                        type="button"
                        className="rounded-md border border-border px-md py-sm text-sm"
                        onClick={() => {
                          setPendingResolution(null);
                          setResolveError(null);
                        }}
                        disabled={resolving}
                      >
                        Cancel
                      </button>
                      <button
                        type="button"
                        className="rounded-md bg-primary px-md py-sm text-sm font-medium text-white hover:bg-primary-hover"
                        onClick={() => void handleResolve()}
                        disabled={resolving}
                      >
                        {resolving ? "Submitting..." : "Confirm"}
                      </button>
                    </div>
                  </div>
                )}
              </>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
