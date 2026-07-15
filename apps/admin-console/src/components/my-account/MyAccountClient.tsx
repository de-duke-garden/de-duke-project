"use client";

import { useEffect, useState } from "react";

/**
 * Screen 31b: Admin -- My Account (FEAT-041). Self-service account
 * management ONLY -- editing the logged-in Staff/Admin's own `fullName`,
 * plus a "Change Password" action distinct from the logged-out forgot-
 * password/reset-password email-link flow (that pair is for a user who
 * isn't currently authenticated at all). This is deliberately NOT a tool
 * for editing another user's profile -- Staff Management (FEAT-033)
 * already covers account-level actions (deactivate/promote) on other
 * internal accounts, but never profile-field edits on someone else's
 * behalf.
 *
 * Calls the same `POST /v1/auth/change-password`/`GET,PATCH
 * /v1/user/profile` endpoints the mobile app's Account Settings screen
 * uses, via the same-origin `/api/backend/...` proxy every client
 * component in this console goes through (see
 * src/app/api/backend/[...path]/route.ts's docstring for why).
 */

interface Profile {
  user_id: string;
  full_name: string;
  email: string | null;
  phone_number: string | null;
  auth_provider: string;
  is_firebase_linked: boolean;
}

type LoadState = "loading" | "loaded" | "error";

export function MyAccountClient() {
  const [state, setState] = useState<LoadState>("loading");
  const [profile, setProfile] = useState<Profile | null>(null);
  const [fullName, setFullName] = useState("");
  const [savingName, setSavingName] = useState(false);
  const [nameSaved, setNameSaved] = useState(false);
  const [nameError, setNameError] = useState<string | null>(null);

  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [changingPassword, setChangingPassword] = useState(false);
  const [passwordError, setPasswordError] = useState<string | null>(null);
  const [passwordChanged, setPasswordChanged] = useState(false);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      try {
        const response = await fetch("/api/backend/v1/user/profile");
        if (!response.ok) throw new Error("Could not load your profile.");
        const body = (await response.json()) as Profile;
        if (cancelled) return;
        setProfile(body);
        setFullName(body.full_name);
        setState("loaded");
      } catch {
        if (!cancelled) setState("error");
      }
    }
    void load();
    return () => {
      cancelled = true;
    };
  }, []);

  async function handleSaveName() {
    setSavingName(true);
    setNameError(null);
    setNameSaved(false);
    try {
      const response = await fetch("/api/backend/v1/user/profile", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ full_name: fullName }),
      });
      if (!response.ok) {
        const body = await response.json().catch(() => null);
        throw new Error(body?.detail ?? "Could not save your name.");
      }
      const updated = (await response.json()) as Profile;
      setProfile(updated);
      setNameSaved(true);
    } catch (e) {
      setNameError(e instanceof Error ? e.message : "Could not save your name.");
    } finally {
      setSavingName(false);
    }
  }

  async function handleChangePassword() {
    setPasswordError(null);
    setPasswordChanged(false);
    if (newPassword !== confirmPassword) {
      setPasswordError("New password and confirmation don't match.");
      return;
    }
    setChangingPassword(true);
    try {
      const response = await fetch("/api/backend/v1/auth/change-password", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          current_password: currentPassword,
          new_password: newPassword,
        }),
      });
      if (!response.ok) {
        const body = await response.json().catch(() => null);
        throw new Error(body?.detail ?? "Could not change your password.");
      }
      setCurrentPassword("");
      setNewPassword("");
      setConfirmPassword("");
      setPasswordChanged(true);
    } catch (e) {
      setPasswordError(e instanceof Error ? e.message : "Could not change your password.");
    } finally {
      setChangingPassword(false);
    }
  }

  if (state === "loading") {
    return <p className="mt-md text-sm text-text-secondary">Loading...</p>;
  }
  if (state === "error" || !profile) {
    return <p className="mt-md text-sm text-error">Could not load your account.</p>;
  }

  return (
    <div className="mt-lg max-w-md space-y-lg">
      <section>
        <h2 className="font-heading text-lg font-semibold">Profile</h2>
        <label className="mt-md block text-sm font-medium" htmlFor="full-name-input">
          Full name
        </label>
        <input
          id="full-name-input"
          type="text"
          className="mt-xs w-full rounded-md border border-border bg-transparent p-sm text-sm"
          value={fullName}
          onChange={(e) => {
            setFullName(e.target.value);
            setNameSaved(false);
          }}
          disabled={savingName}
        />
        {profile.email && (
          <p className="mt-sm text-sm text-text-secondary">Email: {profile.email}</p>
        )}
        {nameError && <p className="mt-xs text-sm text-error">{nameError}</p>}
        <button
          type="button"
          className="mt-sm rounded-md bg-primary px-md py-sm text-sm font-medium text-white hover:bg-primary-hover disabled:opacity-60"
          onClick={handleSaveName}
          disabled={savingName || fullName.trim() === "" || fullName === profile.full_name}
        >
          {savingName ? "Saving..." : "Save name"}
        </button>
        {nameSaved && <p className="mt-xs text-sm text-primary">Saved.</p>}
      </section>

      <section>
        <h2 className="font-heading text-lg font-semibold">Change Password</h2>
        <p className="mt-xs text-sm text-text-secondary">
          Changing your password signs you out of every other active session.
        </p>

        <label className="mt-md block text-sm font-medium" htmlFor="current-password-input">
          Current password
        </label>
        <input
          id="current-password-input"
          type="password"
          className="mt-xs w-full rounded-md border border-border bg-transparent p-sm text-sm"
          value={currentPassword}
          onChange={(e) => setCurrentPassword(e.target.value)}
          disabled={changingPassword}
        />

        <label className="mt-sm block text-sm font-medium" htmlFor="new-password-input">
          New password
        </label>
        <input
          id="new-password-input"
          type="password"
          className="mt-xs w-full rounded-md border border-border bg-transparent p-sm text-sm"
          value={newPassword}
          onChange={(e) => setNewPassword(e.target.value)}
          disabled={changingPassword}
        />

        <label className="mt-sm block text-sm font-medium" htmlFor="confirm-password-input">
          Confirm new password
        </label>
        <input
          id="confirm-password-input"
          type="password"
          className="mt-xs w-full rounded-md border border-border bg-transparent p-sm text-sm"
          value={confirmPassword}
          onChange={(e) => setConfirmPassword(e.target.value)}
          disabled={changingPassword}
        />

        {passwordError && <p className="mt-xs text-sm text-error">{passwordError}</p>}
        <button
          type="button"
          className="mt-sm rounded-md bg-primary px-md py-sm text-sm font-medium text-white hover:bg-primary-hover disabled:opacity-60"
          onClick={handleChangePassword}
          disabled={
            changingPassword ||
            currentPassword === "" ||
            newPassword === "" ||
            confirmPassword === ""
          }
        >
          {changingPassword ? "Changing..." : "Change password"}
        </button>
        {passwordChanged && (
          <p className="mt-xs text-sm text-primary">
            Password changed. Your other sessions have been signed out.
          </p>
        )}
      </section>
    </div>
  );
}
