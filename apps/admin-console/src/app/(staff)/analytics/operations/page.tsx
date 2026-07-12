import { getAdminSession } from "@/lib/auth";
import { OperationsDashboardClient } from "@/components/analytics/OperationsDashboardClient";

/** screens.md Screen 29: Admin Operations Overview -- FEAT-034. Visible
 * to both Staff and Admin. */
export default async function OperationsAnalyticsPage() {
  const session = await getAdminSession();

  if (!session) {
    return (
      <main className="p-lg">
        <h1 className="font-heading text-xl font-semibold">Operations Overview</h1>
        <p className="mt-sm text-text-secondary">
          Sign in with a De-Duke Staff or Admin account to view operations metrics.
        </p>
      </main>
    );
  }

  return (
    <main className="p-lg">
      <h1 className="font-heading text-xl font-semibold">Operations Overview</h1>
      <p className="mt-xs text-text-secondary">
        Moderation, verification, dispute, support, and booking-hold operational health.
      </p>
      <div className="mt-lg">
        <OperationsDashboardClient />
      </div>
    </main>
  );
}
