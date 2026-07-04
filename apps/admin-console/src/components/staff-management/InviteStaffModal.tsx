"use client";

import { useState } from "react";

interface InviteStaffModalProps {
  busy: boolean;
  onSubmit: (fullName: string, email: string) => Promise<void>;
  onClose: () => void;
}

/** "Invite Staff" Modal (screens.md Screen 28) -- name + email, posts to
 * POST /v1/staff-accounts/invite. Validation errors are shown inline
 * (validation-error state), never silently dropped. */
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
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="invite-staff-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-md"
    >
      <form
        onSubmit={handleSubmit}
        className="w-full max-w-sm rounded-lg bg-surface p-lg shadow-lg"
      >
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
          <p role="alert" className="mt-sm text-sm text-red-600">
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
            className="min-h-[48px] min-w-[48px] rounded-md bg-blue-600 px-md py-sm text-white disabled:opacity-60"
          >
            {busy ? "Sending..." : "Send invite"}
          </button>
        </div>
      </form>
    </div>
  );
}
