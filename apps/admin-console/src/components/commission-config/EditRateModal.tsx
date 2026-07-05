"use client";

import { useState } from "react";
import { TRANSACTION_TYPE_LABELS } from "./types";

interface Props {
  transactionType: string;
  currentRate: number | null;
  onCancel: () => void;
  onConfirm: (newRate: number) => Promise<void>;
}

/** Edit rate modal -- FEAT-027 AC: invalid rates (negative or over 100%)
 * are rejected with a clear error, rate not saved. Setting the same rate
 * as current is allowed (screens.md edge case: flagged as a no-op in the
 * history log server-side, not rejected here). */
export function EditRateModal({ transactionType, currentRate, onCancel, onConfirm }: Props) {
  const [value, setValue] = useState(currentRate !== null ? String(currentRate) : "");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleConfirm() {
    const parsed = Number(value);
    if (value.trim() === "" || Number.isNaN(parsed)) {
      setError("Enter a valid number.");
      return;
    }
    if (parsed < 0 || parsed > 100) {
      setError("Rate must be between 0 and 100.");
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      await onConfirm(parsed);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Something went wrong. Please try again.");
      setSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-md">
      <div className="w-full max-w-sm rounded-lg bg-surface p-lg shadow-xl dark:bg-surface-secondary-dark">
        <h2 className="font-heading text-lg font-semibold">
          Edit rate -- {TRANSACTION_TYPE_LABELS[transactionType] ?? transactionType}
        </h2>

        <label className="mt-md block text-sm font-medium" htmlFor="rate-input">
          New rate (%)
        </label>
        <input
          id="rate-input"
          type="number"
          min={0}
          max={100}
          step={0.1}
          className="mt-xs w-full rounded-md border border-border bg-transparent p-sm text-sm"
          value={value}
          onChange={(e) => setValue(e.target.value)}
          disabled={submitting}
        />
        {error && <p className="mt-xs text-sm text-error">{error}</p>}

        <div className="mt-lg flex justify-end gap-sm">
          <button
            type="button"
            className="rounded-md border border-border px-md py-sm text-sm"
            onClick={onCancel}
            disabled={submitting}
          >
            Cancel
          </button>
          <button
            type="button"
            className="rounded-md bg-primary px-md py-sm text-sm font-medium text-white hover:bg-primary-hover"
            onClick={handleConfirm}
            disabled={submitting}
          >
            {submitting ? "Saving..." : "Save"}
          </button>
        </div>
      </div>
    </div>
  );
}
