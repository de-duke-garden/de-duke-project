"use client";

import { useState } from "react";
import { Modal } from "@/components/ui/Modal";
import type { ModerationAction } from "./types";

interface Props {
  action: ModerationAction;
  listingTitle: string;
  onCancel: () => void;
  onConfirm: (reason: string) => Promise<void>;
}

/** Required-reason confirmation modal for approve/ban -- FEAT-025 acceptance
 * criteria: staff cannot ban (or approve) without recording a reason. */
export function ModerationDecisionDialog({ action, listingTitle, onCancel, onConfirm }: Props) {
  const [reason, setReason] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const isBan = action === "ban";
  const trimmedReason = reason.trim();

  async function handleConfirm() {
    if (trimmedReason.length === 0) {
      setError("A reason is required.");
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      await onConfirm(trimmedReason);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Something went wrong. Please try again.");
      setSubmitting(false);
    }
  }

  return (
    <Modal
      labelledBy="moderation-dialog-title"
      size="md"
      onClose={submitting ? undefined : onCancel}
    >
        <h2 id="moderation-dialog-title" className="font-heading text-lg font-semibold">
          {isBan ? "Ban listing" : "Approve listing"}
        </h2>
        <p className="mt-xs text-sm text-text-secondary">{listingTitle}</p>

        <label className="mt-md block text-sm font-medium" htmlFor="moderation-reason">
          Reason {isBan ? "(shown to host)" : "(internal note)"}
        </label>
        <textarea
          id="moderation-reason"
          className="mt-xs w-full rounded-md border border-border bg-transparent p-sm text-sm"
          rows={4}
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          disabled={submitting}
          placeholder={
            isBan
              ? "e.g. Photos do not match the property; suspected duplicate listing"
              : "e.g. Verified against title documents, meets listing standards"
          }
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
            className={`rounded-md px-md py-sm text-sm font-medium text-white ${
              isBan ? "bg-error" : "bg-primary hover:bg-primary-hover"
            }`}
            onClick={handleConfirm}
            disabled={submitting}
          >
            {submitting ? "Submitting..." : isBan ? "Ban listing" : "Approve listing"}
          </button>
        </div>
    </Modal>
  );
}
