"use client";

import { useCallback, useEffect, useState } from "react";

import { CardSection, MetricCard } from "./MetricCard";
import type { BusinessDashboard } from "./types";

const API_BASE_URL = "/api/backend/v1";

type LoadState = "loading" | "loaded" | "empty" | "error";
type RangeDays = 7 | 30 | 90;

async function fetchDashboard(rangeDays: RangeDays): Promise<BusinessDashboard> {
  const since = new Date(Date.now() - rangeDays * 24 * 60 * 60 * 1000).toISOString();
  const response = await fetch(
    `${API_BASE_URL}/analytics/business?since=${encodeURIComponent(since)}`,
  );
  if (!response.ok) {
    if (response.status === 403) {
      throw new Error("You don't have permission to do this.");
    }
    throw new Error(`Failed to load business metrics (${response.status})`);
  }
  return response.json();
}

function money(value: number): string {
  return `₦${value.toLocaleString(undefined, { maximumFractionDigits: 0 })}`;
}

function pct(value: number): string {
  return `${(value * 100).toFixed(1)}%`;
}

function sumValues(record: Record<string, number>): number {
  return Object.values(record).reduce((a, b) => a + b, 0);
}

function formatRecord(record: Record<string, number>): string {
  const entries = Object.entries(record);
  if (entries.length === 0) return "None yet";
  return entries.map(([key, value]) => `${key}: ${value}`).join(", ");
}

/** screens.md Screen 30: Admin Business & Revenue Overview -- FEAT-035,
 * Admin only (enforced server-side by app/api/v1/analytics.py's
 * admin_only dependency -- a Staff-level request gets a 403, rendered
 * here as the same error state, not a hidden link). Same "live query
 * MVP, no real aggregate store yet" caveat as the Operations dashboard --
 * see business_analytics_service.py's header docstring. */
export function BusinessDashboardClient() {
  const [state, setState] = useState<LoadState>("loading");
  const [data, setData] = useState<BusinessDashboard | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [rangeDays, setRangeDays] = useState<RangeDays>(30);

  const load = useCallback(async () => {
    setState("loading");
    try {
      const dashboard = await fetchDashboard(rangeDays);
      setData(dashboard);
      const hasAnyActivity =
        sumValues(dashboard.signups_by_role) > 0 || dashboard.conversion_funnel.booking > 0;
      setState(hasAnyActivity ? "loaded" : "empty");
    } catch (e) {
      setErrorMessage(e instanceof Error ? e.message : "Something went wrong.");
      setState("error");
    }
  }, [rangeDays]);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <>
      <div className="flex gap-sm">
        {([7, 30, 90] as const).map((days) => (
          <button
            key={days}
            type="button"
            className={`rounded-full border px-md py-1 text-sm ${
              rangeDays === days
                ? "border-primary bg-primary text-white"
                : "border-border text-text-secondary"
            }`}
            onClick={() => setRangeDays(days)}
          >
            {days}d
          </button>
        ))}
      </div>

      {state === "loading" && (
        <p className="mt-md text-text-secondary">Loading business metrics...</p>
      )}

      {state === "error" && (
        <div className="mt-md rounded-md border border-error p-md">
          <p className="text-error">{errorMessage}</p>
          <button
            type="button"
            className="mt-sm rounded-md border border-border px-md py-sm text-sm"
            onClick={() => void load()}
          >
            Retry
          </button>
        </div>
      )}

      {state === "empty" && (
        <p className="mt-md text-text-secondary">
          Not enough activity yet in this range to show business metrics.
        </p>
      )}

      {state === "loaded" && data && (
        <>
          <CardSection title="Growth">
            <MetricCard label="New sign-ups" value={sumValues(data.signups_by_role)} sublabel={formatRecord(data.signups_by_role)} />
            <MetricCard
              label="New host verification submissions"
              value={sumValues(data.host_verification_submissions_by_type)}
              sublabel={formatRecord(data.host_verification_submissions_by_type)}
              href="/host-verification"
            />
          </CardSection>

          <CardSection title="Marketplace Liquidity">
            <MetricCard
              label="Active listings"
              value={data.active_listings.by_status.active ?? 0}
              sublabel={formatRecord(data.active_listings.by_type)}
            />
            <MetricCard
              label="Conversion funnel"
              value={`${data.conversion_funnel.view} → ${data.conversion_funnel.inquiry} → ${data.conversion_funnel.booking}`}
              sublabel={
                data.conversion_funnel.search === null
                  ? "View → Inquiry → Booking (search step not yet available)"
                  : `${data.conversion_funnel.search} → View → Inquiry → Booking`
              }
            />
          </CardSection>

          <CardSection title="Revenue">
            <MetricCard
              label="Gross Transaction Value"
              value={money(data.revenue.total_gross_transaction_value)}
            />
            <MetricCard
              label="Commission revenue"
              value={money(data.revenue.total_commission_revenue)}
              sublabel={`Take rate ${pct(data.revenue.overall_take_rate)}`}
              href="/commission-config"
            />
            <MetricCard
              label="Leakage rate"
              value="Not yet available"
              sublabel="Requires FEAT-016 (Phase 3)"
            />
          </CardSection>

          <CardSection title="Agency Tier">
            <MetricCard
              label="Free-to-Agency conversion / churn"
              value="Not yet available"
              sublabel="Agency Tier subscription ships in Phase 3"
            />
          </CardSection>
        </>
      )}
    </>
  );
}
