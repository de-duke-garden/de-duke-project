"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

/** Admin Web Console sign-in -- Staff/Admin accounts only (FEAT-033).
 *
 * Reuses the same backend credential (email + password) as the mobile
 * app's FEAT-001 login -- De-Duke Staff/Admin accounts are just User rows
 * with role=deduke_staff/deduke_admin, created via invite (FEAT-033) or
 * the CLI bootstrap script, never self-signup.
 */
export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setSubmitting(true);
    setError(null);

    try {
      const response = await fetch("/api/session", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, password }),
      });

      if (!response.ok) {
        const body = await response.json().catch(() => ({}));
        setError(body.detail ?? "Sign-in failed. Please try again.");
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
      <form
        onSubmit={handleSubmit}
        className="w-full max-w-sm rounded-lg bg-surface p-lg shadow-md dark:bg-surface-dark"
      >
        <h1 className="font-heading text-xl font-semibold text-text-primary dark:text-text-primary-dark">
          De-Duke Admin Console
        </h1>
        <p className="mt-xs mb-lg text-sm text-text-secondary dark:text-text-secondary-dark">
          Sign in with your Staff or Admin account.
        </p>

        {error && (
          <div
            role="alert"
            className="mb-md rounded-md border border-error bg-error/10 p-sm text-sm text-error"
          >
            {error}
          </div>
        )}

        <label className="mb-xs block text-sm font-medium text-text-primary dark:text-text-primary-dark">
          Email
        </label>
        <input
          type="email"
          required
          autoComplete="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          disabled={submitting}
          className="mb-md w-full rounded-md border border-border bg-surface-secondary p-sm text-text-primary focus-visible:outline-none dark:border-border-dark dark:bg-surface-secondary-dark dark:text-text-primary-dark"
        />

        <label className="mb-xs block text-sm font-medium text-text-primary dark:text-text-primary-dark">
          Password
        </label>
        <input
          type="password"
          required
          autoComplete="current-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          disabled={submitting}
          className="mb-lg w-full rounded-md border border-border bg-surface-secondary p-sm text-text-primary focus-visible:outline-none dark:border-border-dark dark:bg-surface-secondary-dark dark:text-text-primary-dark"
        />

        <button
          type="submit"
          disabled={submitting}
          className="w-full rounded-md bg-primary p-sm font-medium text-white disabled:opacity-60"
        >
          {submitting ? "Signing in..." : "Sign in"}
        </button>
      </form>
    </main>
  );
}
