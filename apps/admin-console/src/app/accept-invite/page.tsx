"use client";

import { Suspense, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";

/** FEAT-033 AC: "the invitee sets their own password via an emailed
 * invitation link." An Admin invites a Staff member via
 * StaffAccountsClient -> POST /v1/staff-accounts/invite, which emails a
 * link of the form `{admin_console_url}/accept-invite?token=...&uid=...`
 * (app/api/v1/staff_accounts.py) -- this page is that destination.
 *
 * Public/unauthenticated by design (see middleware.ts's PUBLIC_PATHS) --
 * a brand-new invitee has no session yet.
 */
function AcceptInviteForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const token = searchParams.get("token") ?? "";
  const uid = searchParams.get("uid") ?? "";

  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const linkIncomplete = !token || !uid;

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    if (password.length < 8) {
      setError("Password must be at least 8 characters.");
      return;
    }
    if (password !== confirmPassword) {
      setError("Passwords don't match.");
      return;
    }

    setSubmitting(true);
    try {
      const response = await fetch("/api/session/accept-invite", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ userId: uid, inviteToken: token, newPassword: password }),
      });

      if (!response.ok) {
        const body = await response.json().catch(() => ({}));
        setError(body.detail ?? "This invite link is invalid or has already been used.");
        setSubmitting(false);
        return;
      }

      router.replace("/");
      router.refresh();
    } catch {
      setError("Could not reach the server. Check your connection and try again.");
      setSubmitting(false);
    }
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-surface-secondary p-md dark:bg-surface-secondary-dark">
      <div className="w-full max-w-sm rounded-lg bg-surface p-lg shadow-md dark:bg-surface-dark">
        <h1 className="font-heading text-xl font-semibold text-text-primary dark:text-text-primary-dark">
          Accept your invite
        </h1>
        <p className="mt-xs mb-lg text-sm text-text-secondary dark:text-text-secondary-dark">
          Choose a password to finish setting up your De-Duke Admin Console account.
        </p>

        {linkIncomplete ? (
          <div
            role="alert"
            className="rounded-md border border-error bg-error/10 p-sm text-sm text-error"
          >
            This invite link is missing required details. Copy the full link from your invite
            email and open it again.
          </div>
        ) : (
          <form onSubmit={handleSubmit}>
            {error && (
              <div
                role="alert"
                className="mb-md rounded-md border border-error bg-error/10 p-sm text-sm text-error"
              >
                {error}
              </div>
            )}

            <label className="mb-xs block text-sm font-medium text-text-primary dark:text-text-primary-dark">
              New password
            </label>
            <input
              type="password"
              required
              autoComplete="new-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              disabled={submitting}
              className="mb-md w-full rounded-md border border-border bg-surface-secondary p-sm text-text-primary focus-visible:outline-none dark:border-border-dark dark:bg-surface-secondary-dark dark:text-text-primary-dark"
            />

            <label className="mb-xs block text-sm font-medium text-text-primary dark:text-text-primary-dark">
              Confirm password
            </label>
            <input
              type="password"
              required
              autoComplete="new-password"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              disabled={submitting}
              className="mb-lg w-full rounded-md border border-border bg-surface-secondary p-sm text-text-primary focus-visible:outline-none dark:border-border-dark dark:bg-surface-secondary-dark dark:text-text-primary-dark"
            />

            <button
              type="submit"
              disabled={submitting}
              className="w-full rounded-md bg-primary p-sm font-medium text-white disabled:opacity-60"
            >
              {submitting ? "Setting password..." : "Set password & sign in"}
            </button>
          </form>
        )}
      </div>
    </main>
  );
}

export default function AcceptInvitePage() {
  return (
    <Suspense>
      <AcceptInviteForm />
    </Suspense>
  );
}
