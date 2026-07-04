"use client";

import { useCallback, useEffect, useState } from "react";

import { ConfirmModal } from "./ConfirmModal";
import { InviteStaffModal } from "./InviteStaffModal";
import type { StaffAccount } from "./types";

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8000/v1";

type PendingAction = {
  account: StaffAccount;
  kind: "deactivate" | "reactivate" | "promote" | "demote";
};

const ACTION_COPY: Record<
  PendingAction["kind"],
  { title: string; confirmLabel: string; endpoint: string }
> = {
  deactivate: { title: "Deactivate this account?", confirmLabel: "Deactivate", endpoint: "deactivate" },
  reactivate: { title: "Reactivate this account?", confirmLabel: "Reactivate", endpoint: "reactivate" },
  promote: { title: "Promote to Admin?", confirmLabel: "Promote", endpoint: "promote" },
  demote: { title: "Demote to Staff?", confirmLabel: "Demote", endpoint: "demote" },
};

export function StaffAccountsClient() {
  const [accounts, setAccounts] = useState<StaffAccount[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [showInvite, setShowInvite] = useState(false);
  const [inviteBusy, setInviteBusy] = useState(false);
  const [inviteLink, setInviteLink] = useState<string | null>(null);
  const [pendingAction, setPendingAction] = useState<PendingAction | null>(null);
  const [actionBusy, setActionBusy] = useState(false);

  const loadAccounts = useCallback(async () => {
    setError(null);
    try {
      const response = await fetch(API_BASE_URL + "/staff-accounts", { credentials: "include" });
      if (response.status === 403) {
        setError("You do not have permission to do this.");
        setAccounts([]);
        return;
      }
      if (response.ok === false) {
        setError("Could not load staff accounts. Try again shortly.");
        setAccounts([]);
        return;
      }
      setAccounts(await response.json());
    } catch {
      setError("Could not reach the server. Check your connection and try again.");
      setAccounts([]);
    }
  }, []);

  useEffect(() => {
    loadAccounts();
  }, [loadAccounts]);

  async function handleInvite(fullName: string, email: string) {
    setInviteBusy(true);
    try {
      const response = await fetch(API_BASE_URL + "/staff-accounts/invite", {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ full_name: fullName, email }),
      });
      const body = await response.json();
      if (response.ok === false) {
        setError(body.detail ?? "Could not send the invite.");
        setInviteBusy(false);
        return;
      }
      setInviteLink(body.invite_link);
      setShowInvite(false);
      setInviteBusy(false);
      await loadAccounts();
    } catch {
      setError("Could not reach the server. Check your connection and try again.");
      setInviteBusy(false);
    }
  }

  async function handleConfirmAction() {
    if (pendingAction === null) return;
    setActionBusy(true);
    const endpoint = ACTION_COPY[pendingAction.kind].endpoint;
    try {
      const response = await fetch(
        API_BASE_URL + "/staff-accounts/" + pendingAction.account.id + "/" + endpoint,
        { method: "POST", credentials: "include" },
      );
      const body = await response.json().catch(() => ({}));
      if (response.ok === false) {
        setError(body.detail ?? "That action could not be completed.");
      }
      setPendingAction(null);
      setActionBusy(false);
      await loadAccounts();
    } catch {
      setError("Could not reach the server. Check your connection and try again.");
      setActionBusy(false);
    }
  }

  if (accounts === null) {
    return <p className="mt-lg text-text-secondary">Loading staff accounts...</p>;
  }

  return (
    <div className="mt-lg">
      {error && (
        <div role="alert" className="mb-md rounded-md border border-error bg-error/10 p-sm text-sm text-error">
          {error}
        </div>
      )}

      {inviteLink && (
        <div className="mb-md rounded-md border border-primary bg-primary-light p-sm text-sm">
          Invite created. Share this one-time link with the new staff member (email dispatch is
          not yet wired up): <code className="break-all">{inviteLink}</code>
        </div>
      )}

      <div className="mb-md flex justify-end">
        <button
          onClick={() => setShowInvite(true)}
          className="min-h-[48px] rounded-md bg-primary px-md py-sm font-medium text-white"
        >
          Invite Staff
        </button>
      </div>

      {accounts.length === 0 ? (
        <p className="text-text-secondary">No staff accounts yet.</p>
      ) : (
        <table className="w-full border-collapse text-left text-sm">
          <thead>
            <tr className="border-b border-border dark:border-border-dark">
              <th className="p-sm">Name</th>
              <th className="p-sm">Email</th>
              <th className="p-sm">Role</th>
              <th className="p-sm">Status</th>
              <th className="p-sm">Actions</th>
            </tr>
          </thead>
          <tbody>
            {accounts.map((account) => (
              <tr key={account.id} className="border-b border-border dark:border-border-dark">
                <td className="p-sm">{account.full_name}</td>
                <td className="p-sm">{account.email ?? "--"}</td>
                <td className="p-sm capitalize">{account.role.replace("deduke_", "")}</td>
                <td className="p-sm">{account.is_active ? "Active" : "Deactivated"}</td>
                <td className="p-sm">
                  <div className="flex flex-wrap gap-xs">
                    {account.is_active ? (
                      <button
                        className="text-error underline"
                        onClick={() => setPendingAction({ account, kind: "deactivate" })}
                      >
                        Deactivate
                      </button>
                    ) : (
                      <button
                        className="text-primary underline"
                        onClick={() => setPendingAction({ account, kind: "reactivate" })}
                      >
                        Reactivate
                      </button>
                    )}
                    {account.role === "deduke_staff" ? (
                      <button
                        className="text-primary underline"
                        onClick={() => setPendingAction({ account, kind: "promote" })}
                      >
                        Promote to Admin
                      </button>
                    ) : (
                      <button
                        className="text-text-secondary underline"
                        onClick={() => setPendingAction({ account, kind: "demote" })}
                      >
                        Demote to Staff
                      </button>
                    )}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {showInvite && (
        <InviteStaffModal
          busy={inviteBusy}
          onSubmit={handleInvite}
          onClose={() => setShowInvite(false)}
        />
      )}

      {pendingAction && (
        <ConfirmModal
          title={ACTION_COPY[pendingAction.kind].title}
          description={
            pendingAction.account.full_name +
            " (" +
            (pendingAction.account.email ?? "no email") +
            ")"
          }
          confirmLabel={ACTION_COPY[pendingAction.kind].confirmLabel}
          busy={actionBusy}
          onConfirm={handleConfirmAction}
          onCancel={() => setPendingAction(null)}
        />
      )}
    </div>
  );
}
