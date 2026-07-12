"use client";

import { useCallback, useEffect, useState } from "react";

import { CardSection, MetricCard } from "./MetricCard";
import type { OperationsDashboard } from "./types";

const API_BASE_URL = "/api/backend/v1";

type LoadState = "loading" | "loaded" | "empty" | "error";

async function fetchDashboard(): Promise<OperationsDashboard> {
  const response = await fetch(`${API_BASE_URL}/analytics/operations`);
  if (!response.ok) {
    throw new Error(`Failed to load operations metrics (${response.status})`);
  }
  return response.json();
}

function pct(value: number): string {
  return `${(value * 100).toFixed(1)}%`;
}

function hours(value: number): string {
  return `${value.toFixed(1)}h`;
}

/** screens.md Screen 29: Admin Operations Overview -- FEAT-034.
 *
 * NOTE: unlike the doc's spec (metrics from a periodically-refreshed
 * aggregate store, with a 7/30/90-day range selector), this reads a
 * current-snapshot live aggregate from the Primary Database and has no
 * date-range selector yet -- see app/services/ops_analytics_service.py's
 * header docstring for why (no Product Analytics Platform is
 * provisioned yet to materialize a real aggregate store from). */
export function OperationsDashboardClient() {
  const [state, setState] = useState<LoadState>("loading");
  const [data, setData] = useState<OperationsDashboard | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const load = useCallback(async () => {
    setState("loading");
    try {
      const dashboard = await fetchDashboard();
      setData(dashboard);
      const hasAnyActivity =
        dashboard.moderation_queue.queue_size > 0 ||
        dashboard.host_verification.queue_size > 0 ||
        dashboard.disputes.open_count + dashboard.disputes.resolved_count > 0 ||
        dashboard.booking_holds.total_holds > 0;
      setState(hasAnyActivity ? "loaded" : "empty");
    } catch (e) {
      setErrorMessage(e instanceof Error ? e.message : "Something went wrong.");
      setState("error");
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  if (state === "loading") {
    return <p className="text-text-secondary">Loading operations metrics...</p>;
  }

  if (state === "error") {
    return (
      <div className="rounded-md border border-error p-md">
        <p className="text-error">{errorMessage}</p>
        <button
          type="button"
          className="mt-sm rounded-md border border-border px-md py-sm text-sm"
          onClick={() => void load()}
        >
          Retry
        </button>
      </div>
    );
  }

  if (state === "empty" || !data) {
    return <p className="text-text-secondary">Not enough activity yet to show operations metrics.</p>;
  }

  const workloadEntries = Object.entries(data.staff_workload);

  return (
    <>
      <CardSection title="Moderation & Verification">
        <MetricCard
          label="Moderation Queue size"
          value={data.moderation_queue.queue_size}
          sublabel={`Avg age ${hours(data.moderation_queue.avg_age_hours)}`}
          href="/moderation-queue"
        />
        <MetricCard
          label="Host Verification Review size"
          value={data.host_verification.queue_size}
          sublabel={`Avg age ${hours(data.host_verification.avg_age_hours)}`}
          href="/host-verification"
        />
      </CardSection>

      <CardSection title="Trust & Safety">
        <MetricCard
          label="Open disputes"
          value={data.disputes.open_count}
          href="/disputes"
        />
        <MetricCard
          label="Resolved disputes"
          value={data.disputes.resolved_count}
          sublabel={`Avg resolution time ${hours(data.disputes.avg_resolution_hours)}`}
          href="/disputes"
        />
      </CardSection>

      <CardSection title="Support">
        {/* screens.md Screen 29 AC: Support Inbox volume/first-response
         * time. Genuinely unavailable -- that data lives in Firestore, out
         * of reach of this Primary-Database-only aggregation (see
         * ops_analytics_service.py's header docstring). Shown honestly
         * rather than fabricated. */}
        <MetricCard
          label="Support Inbox"
          value="Not yet available"
          sublabel="Requires Firestore support-event aggregation"
          href="/support"
        />
      </CardSection>

      <CardSection title="Bookings">
        <MetricCard
          label="Hold-to-payment conversion"
          value={pct(data.booking_holds.hold_to_payment_conversion_rate)}
          sublabel={`${data.booking_holds.total_holds} total holds`}
        />
        <MetricCard
          label="Hold-expiry rate"
          value={pct(data.booking_holds.hold_expiry_rate)}
        />
      </CardSection>

      <section className="mt-lg">
        <h2 className="font-heading text-sm font-semibold uppercase tracking-wide text-text-secondary">
          Team Workload
        </h2>
        {workloadEntries.length === 0 ? (
          <p className="mt-sm text-text-secondary">No open items currently assigned to staff.</p>
        ) : (
          <ul className="mt-sm space-y-xs">
            {workloadEntries.map(([staffId, count]) => (
              <li key={staffId} className="flex justify-between border-b border-border py-xs text-sm">
                <span>{staffId}</span>
                <span className="font-medium">{count}</span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </>
  );
}
