"use client";

import { Modal } from "@/components/ui/Modal";

interface ConfirmModalProps {
  title: string;
  description: string;
  confirmLabel: string;
  busy: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

/** Generic confirmation modal used before any destructive/high-impact
 * staff-account action (deactivate, promote, demote) -- screens.md Screen
 * 28 requires a confirmation Modal for each of these actions. Renders
 * through the shared `Modal` shell so it picks up `modal-enter`. */
export function ConfirmModal({
  title,
  description,
  confirmLabel,
  busy,
  onConfirm,
  onCancel,
}: ConfirmModalProps) {
  return (
    <Modal onClose={onCancel} labelledBy="confirm-modal-title" size="sm">
      <h2 id="confirm-modal-title" className="text-lg font-semibold">
        {title}
      </h2>
      <p className="mt-sm text-text-secondary">{description}</p>
      <div className="mt-lg flex justify-end gap-sm">
        <button
          type="button"
          onClick={onCancel}
          disabled={busy}
          className="min-h-[48px] min-w-[48px] rounded-md border px-md py-sm"
        >
          Cancel
        </button>
        <button
          type="button"
          onClick={onConfirm}
          disabled={busy}
          className="min-h-[48px] min-w-[48px] rounded-md bg-error px-md py-sm text-white disabled:opacity-60"
        >
          {busy ? "Working..." : confirmLabel}
        </button>
      </div>
    </Modal>
  );
}
