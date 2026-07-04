"use client";

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
 * 28 requires a confirmation Modal for each of these actions. */
export function ConfirmModal({
  title,
  description,
  confirmLabel,
  busy,
  onConfirm,
  onCancel,
}: ConfirmModalProps) {
  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="confirm-modal-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-md"
    >
      <div className="w-full max-w-sm rounded-lg bg-surface p-lg shadow-lg">
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
            className="min-h-[48px] min-w-[48px] rounded-md bg-red-600 px-md py-sm text-white disabled:opacity-60"
          >
            {busy ? "Working..." : confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
