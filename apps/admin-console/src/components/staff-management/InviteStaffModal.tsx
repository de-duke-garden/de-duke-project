"use client";

import { useState } from "react";

import { Modal } from "@/components/ui/Modal";

interface InviteStaffModalProps {
  busy: boolean;
  onSubmit: (fullName: string, email: string) => Promise<void>;
  onClose: () => void;
}

/** "Invite Staff" Modal (screens.md Screen 28) -- name + email, posts to
 * POST /v1/staff-accounts/invite. Validation errors are shown inline
 * (validation-error state), never silently dropped. Renders through the
 * shared `Modal` shell so it picks up `modal-enter`. */
export function InviteStaffModal({ busy, onSubmit, onClose }: InviteStaffModalProps) {
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [validationError, setValidationError] = useState<string | null>(null);

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!fullName.trim()) {
      setValidationError("Full name is required.");
      return;
    }
    if (!email.trim() || !email.includes("@")) {
      setValidationError("Enter a valid email address.");
      return;
    }
    setValidationError(null);
    await onSubmit(fullName.trim(), email.trim());
  };

  return (
    <Modal onClose={onClose} labelledBy="invite-staff-title" size="sm">
      <form onSubmit={handleSubmit}>
        <h2 id="invite-staff-title" className="text-lg font-semibold">
          Invite Staff
        </h2>

        <label className="mt-md block text-sm font-medium" htmlFor="invite-full-name">
          Full name
        </label>
        <input
          id="invite-full-name"
          type="text"
          value={fullName}
          onChange={(event) => setFullName(event.target.value)}
          className="mt-xs min-h-[48px] w-full rounded-md border px-sm"
          disabled={busy}
        />

        <label className="mt-md block text-sm font-medium" htmlFor="invite-email">
          Email
        </label>
        <input
          id="invite-email"
          type="email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          className="mt-xs min-h-[48px] w-full rounded-md border px-sm"
          disabled={busy}
        />

        {validationError ? (
          <p role="alert" className="mt-sm text-sm text-error">
            {validationError}
          </p>
        ) : null}

        <div className="mt-lg flex justify-end gap-sm">
          <button
            type="button"
            onClick={onClose}
            disabled={busy}
            className="min-h-[48px] min-w-[48px] rounded-md border px-md py-sm"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={busy}
            className="min-h-[48px] min-w-[48px] rounded-md bg-primary px-md py-sm text-white disabled:opacity-60"
          >
            {busy ? "Sending..." : "Send invite"}
          </button>
        </div>
      </form>
    </Modal>
  );
}
