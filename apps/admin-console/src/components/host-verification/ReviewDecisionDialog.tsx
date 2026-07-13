"use client";

import { useState } from "react";
import { Modal } from "@/components/ui/Modal";
import type { ReviewDecision } from "./types";

interface Props {
  decision: ReviewDecision;
  submissionLabel: string;
  onCancel: () => void;
  onConfirm: (reason: string | undefined) => Promise<void>;
}

/** Verify/Reject confirmation modal -- FEAT-002 AC: rejecting a submission
 * always requires a reason; verifying does not. */
export function ReviewDecisionDialog({ decision, submissionLabel, onCancel, onConfirm }: Props) {
  const [reason, setReason] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const isReject = decision === "rejected";

  async function handleConfirm() {
    const trimmed = reason.trim();
    if (isReject && trimmed.length === 0) {
      setError("A reason is required when rejecting a submission.");
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      await onConfirm(isReject ? trimmed : undefined);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Something went wrong. Please try again.");
      setSubmitting(false);
    }
  }

  return (
    <Modal size="md" labelledBy="review-decision-heading" onClose={() => !submitting && onCancel()}>
      <h2 id="review-decision-heading" className="font-heading text-lg font-semibold">
        {isReject ? "Reject submission" : "Verify submission"}
      </h2>
      <p className="mt-xs text-sm text-text-secondary">{submissionLabel}</p>

      {isReject && (
        <>
          <label className="mt-md block text-sm font-medium" htmlFor="review-reason">
            Reason (shown to the applicant)
          </label>
          <textarea
            id="review-reason"
            className="mt-xs w-full rounded-md border border-border bg-transparent p-sm text-sm"
            rows={4}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            disabled={submitting}
            placeholder="e.g. Practicing certificate image is unclear, please resubmit"
          />
        </>
      )}
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
            isReject ? "bg-error" : "bg-primary hover:bg-primary-hover"
          }`}
          onClick={handleConfirm}
          disabled={submitting}
        >
          {submitting ? "Submitting..." : isReject ? "Reject" : "Verify"}
        </button>
      </div>
    </Modal>
  );
}
