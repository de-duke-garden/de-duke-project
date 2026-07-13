"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { Firestore } from "firebase/firestore";

import { CardGridSkeleton } from "@/components/ui/Skeleton";
import { signInToChat } from "@/lib/firebaseChat";
import { getConversationsNeedingAttentionCount, getSupportUnresolvedCount } from "@/lib/firestoreCounts";
import type { OperationsDashboard, BusinessDashboard } from "@/components/analytics/types";

import { SummaryCard } from "./SummaryCard";
import { PreviewCard } from "./PreviewCard";

const API_BASE_URL = "/api/backend/v1";

type QueueKey = "hostVerification" | "disputes" | "moderation" | "support" | "staffAttention";

type QueueState = Record<QueueKey, number | "error" | null>; // null = still loading

type ScreenState = "loading" | "ready" | "full-error";

async function requestChatToken(): Promise<string> {
  const response = await fetch("/api/backend/v1/chat/token", { method: "POST" });
  if (!response.ok) {
    const body = await response.json().catch(() => null);
    throw new Error(body?.detail ?? `Could not obtain a chat session (${response.status})`);
  }
  const body = await response.json();
  return body.firebase_custom_token as string;
}

async function fetchOperations(): Promise<OperationsDashboard> {
  const response = await fetch(`${API_BASE_URL}/analytics/operations`);
  if (!response.ok) throw new Error(`Failed to load operations metrics (${response.status})`);
  return response.json();
}

async function fetchBusiness(): Promise<BusinessDashboard> {
  const response = await fetch(`${API_BASE_URL}/analytics/business`);
  if (!response.ok) throw new Error(`Failed to load business metrics (${response.status})`);
  return response.json();
}

async function fetchActiveStaffCount(): Promise<number> {
  const response = await fetch(`${API_BASE_URL}/staff-accounts`);
  if (!response.ok) throw new Error(`Failed to load staff accounts (${response.status})`);
  const accounts: Array<{ is_active: boolean }> = await response.json();
  return accounts.filter((a) => a.is_active).length;
}

/**
 * screens.md Screen 22: Admin -- Home / Overview. The Admin Web Console's
 * root landing screen (route `/`, wired via app/page.tsx + AdminNav's
 * "Home" link) -- one summary card per module, urgency-ordered, each
 * backed by its own query so a slow/failed module never blocks the rest
 * (Partial Load state).
 *
 * Deviation from the doc's literal per-module endpoint list: the
 * Moderation Queue, Host Verification, and Open Disputes counts are all
 * read from the single GET /analytics/operations aggregate (FEAT-034)
 * rather than three separate `?count=true` endpoints -- that endpoint
 * already computes exactly these three counts in one lightweight query,
 * so adding three near-duplicate count-only endpoints would be pure
 * ceremony. The tradeoff (documented, not hidden): those three cards rise
 * or fall together if that one query fails, rather than failing
 * independently. Support Inbox and Conversations Needing Staff Attention
 * remain genuinely independent Firestore aggregate counts, since that data
 * has no backend REST endpoint at all (chat/support live directly in
 * Firestore, per firebaseChat.ts).
 */
export function HomeDashboardClient({ isAdmin }: { isAdmin: boolean }) {
  const [screenState, setScreenState] = useState<ScreenState>("loading");
  const [queues, setQueues] = useState<QueueState>({
    hostVerification: null,
    disputes: null,
    moderation: null,
    support: null,
    staffAttention: null,
  });
  const [operationsPreview, setOperationsPreview] = useState<OperationsDashboard | "error" | null>(null);
  const [businessPreview, setBusinessPreview] = useState<BusinessDashboard | "error" | null>(null);
  const [staffCount, setStaffCount] = useState<number | "error" | null>(null);

  const load = useCallback(() => {
    setScreenState("loading");
    setQueues({
      hostVerification: null,
      disputes: null,
      moderation: null,
      support: null,
      staffAttention: null,
    });
    setOperationsPreview(null);
    setBusinessPreview(isAdmin ? null : null);
    setStaffCount(isAdmin ? null : null);

    // Operations aggregate -- backs three queue cards plus the Operations
    // preview card. Fired once, fanned out to four pieces of state.
    void fetchOperations()
      .then((data) => {
        setOperationsPreview(data);
        setQueues((prev) => ({
          ...prev,
          hostVerification: data.host_verification.queue_size,
          disputes: data.disputes.open_count,
          moderation: data.moderation_queue.queue_size,
        }));
      })
      .catch(() => {
        setOperationsPreview("error");
        setQueues((prev) => ({
          ...prev,
          hostVerification: "error",
          disputes: "error",
          moderation: "error",
        }));
      });

    // Firestore-backed counts (Support Inbox, Conversations Needing Staff
    // Attention) -- independent of the operations aggregate and of each
    // other; both are chained off a single sign-in exchange.
    void requestChatToken()
      .then(signInToChat)
      .then(async (db: Firestore) => {
        void getSupportUnresolvedCount(db)
          .then((count) => setQueues((prev) => ({ ...prev, support: count })))
          .catch(() => setQueues((prev) => ({ ...prev, support: "error" })));

        void getConversationsNeedingAttentionCount(db)
          .then((count) => setQueues((prev) => ({ ...prev, staffAttention: count })))
          .catch(() => setQueues((prev) => ({ ...prev, staffAttention: "error" })));
      })
      .catch(() => {
        // Not configured (ChatUnavailableError) or sign-in failed -- both
        // cards show "Couldn't load" rather than the whole screen failing.
        setQueues((prev) => ({ ...prev, support: "error", staffAttention: "error" }));
      });

    if (isAdmin) {
      void fetchBusiness()
        .then(setBusinessPreview)
        .catch(() => setBusinessPreview("error"));
      void fetchActiveStaffCount()
        .then(setStaffCount)
        .catch(() => setStaffCount("error"));
    }
  }, [isAdmin]);

  useEffect(() => {
    load();
  }, [load]);

  // Screen-level state: "loading" until every query has settled at least
  // once; "full-error" only when literally everything failed.
  useEffect(() => {
    const queueValues = Object.values(queues);
    const stillLoading =
      queueValues.some((v) => v === null) ||
      operationsPreview === null ||
      (isAdmin && (businessPreview === null || staffCount === null));
    if (stillLoading) {
      setScreenState("loading");
      return;
    }
    const everythingFailed =
      queueValues.every((v) => v === "error") &&
      operationsPreview === "error" &&
      (!isAdmin || (businessPreview === "error" && staffCount === "error"));
    setScreenState(everythingFailed ? "full-error" : "ready");
  }, [queues, operationsPreview, businessPreview, staffCount, isAdmin]);

  const queueCards = useMemo(() => {
    const specs: Array<{
      key: QueueKey;
      title: string;
      href: string;
      allClearLabel: string;
      countLabel: (count: number) => string;
    }> = [
      {
        key: "hostVerification",
        title: "Pending Host Verifications",
        href: "/host-verification",
        allClearLabel: "All clear -- no submissions waiting",
        countLabel: (n) => `${n} awaiting review`,
      },
      {
        key: "disputes",
        title: "Open Disputes",
        href: "/disputes",
        allClearLabel: "All clear -- no open disputes",
        countLabel: (n) => `${n} open`,
      },
      {
        key: "moderation",
        title: "Moderation Queue",
        href: "/moderation-queue",
        allClearLabel: "All clear -- queue is empty",
        countLabel: (n) => `${n} awaiting action`,
      },
      {
        key: "support",
        title: "General Support Inbox",
        href: "/support",
        allClearLabel: "All clear -- no unresolved conversations",
        countLabel: (n) => `${n} unresolved`,
      },
      {
        key: "staffAttention",
        title: "Conversations Needing Staff Attention",
        href: "/conversations",
        allClearLabel: "All clear -- nothing waiting on staff",
        countLabel: (n) => `${n} unassigned`,
      },
    ];

    // Urgency order: non-zero queues first (descending), zero/all-clear
    // queues after, failed queries last (their number is unknown, not
    // necessarily urgent) -- screens.md "ordered by urgency" requirement.
    return [...specs].sort((a, b) => {
      const av = queues[a.key];
      const bv = queues[b.key];
      const rank = (v: number | "error" | null) => (v === "error" || v === null ? -1 : v);
      return rank(bv) - rank(av);
    });
  }, [queues]);

  if (screenState === "loading") {
    return <CardGridSkeleton count={isAdmin ? 8 : 6} />;
  }

  if (screenState === "full-error") {
    return (
      <div className="rounded-md border border-error p-lg text-center">
        <p className="text-error">Couldn&apos;t load the Home dashboard.</p>
        <button
          type="button"
          className="mt-sm rounded-md border border-border px-md py-sm text-sm"
          onClick={() => load()}
        >
          Retry
        </button>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 gap-md sm:grid-cols-2 lg:grid-cols-3">
      {queueCards.map((spec, i) => (
        <SummaryCard
          key={spec.key}
          index={i}
          title={spec.title}
          href={spec.href}
          value={queues[spec.key]}
          allClearLabel={spec.allClearLabel}
          countLabel={spec.countLabel}
          onRetry={load}
        />
      ))}

      <PreviewCard
        index={queueCards.length}
        title="Operations Overview"
        href="/analytics/operations"
        state={operationsPreview}
        renderMetrics={(data) => [
          { label: "Active listings holds", value: data.booking_holds.total_holds },
          {
            label: "Hold-to-payment rate",
            value: `${(data.booking_holds.hold_to_payment_conversion_rate * 100).toFixed(1)}%`,
          },
        ]}
      />

      {isAdmin && (
        <PreviewCard
          index={queueCards.length + 1}
          title="Business & Revenue Overview"
          href="/analytics/business"
          state={businessPreview}
          renderMetrics={(data) => [
            {
              label: "Gross transaction value",
              value: `₦${data.revenue.total_gross_transaction_value.toLocaleString(undefined, {
                maximumFractionDigits: 0,
              })}`,
            },
            {
              label: "Commission collected",
              value: `₦${data.revenue.total_commission_revenue.toLocaleString(undefined, {
                maximumFractionDigits: 0,
              })}`,
            },
          ]}
        />
      )}

      {isAdmin && (
        <SummaryCard
          index={queueCards.length + 2}
          title="Staff Management"
          href="/staff-management"
          value={staffCount}
          allClearLabel="No active staff yet"
          countLabel={(n) => `${n} active staff`}
          onRetry={load}
        />
      )}
    </div>
  );
}
