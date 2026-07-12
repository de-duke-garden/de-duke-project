import { getAdminSession } from "@/lib/auth";
import { BusinessDashboardClient } from "@/components/analytics/BusinessDashboardClient";

/** screens.md Screen 30: Admin Business & Revenue Overview -- FEAT-035,
 * Admin only. AC: "This dashboard is not accessible to Staff-level
 * accounts -- attempting to reach it directly shows a 'You don't have
 * permission to do this' state." Gated here (server-rendered) in
 * addition to the Backend API Service's own require_roles(DEDUKE_ADMIN)
 * on GET /v1/analytics/business -- never rely on hiding the sidebar link
 * alone (AGENTS.md).
 */
export default async function BusinessAnalyticsPage() {
  const session = await getAdminSession();

  if (!session) {
    return (
      <main className="p-lg">
        <h1 className="font-heading text-xl font-semibold">Business &amp; Revenue Overview</h1>
        <p className="mt-sm text-text-secondary">
          Sign in with a De-Duke Admin account to view business metrics.
        </p>
      </main>
    );
  }

  if (session.role !== "deduke_admin") {
    return (
      <main className="p-lg">
        <h1 className="font-heading text-xl font-semibold">Business &amp; Revenue Overview</h1>
        <p className="mt-sm text-error">You don&apos;t have permission to do this.</p>
      </main>
    );
  }

  return (
    <main className="p-lg">
      <h1 className="font-heading text-xl font-semibold">Business &amp; Revenue Overview</h1>
      <p className="mt-xs text-text-secondary">
        Growth, marketplace liquidity, and revenue metrics.
      </p>
      <div className="mt-lg">
        <BusinessDashboardClient />
      </div>
    </main>
  );
}
