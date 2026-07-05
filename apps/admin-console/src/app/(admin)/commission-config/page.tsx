import { getAdminSession } from "@/lib/auth";
import { CommissionConfigClient } from "@/components/commission-config/CommissionConfigClient";

/** screens.md Screen 25: Admin Commission Rate Configuration -- FEAT-027.
 *
 * Staff can view read-only (for context, e.g. while resolving a dispute);
 * only Admin can edit. The Edit action is hidden (not disabled) for Staff
 * here, but the real enforcement is server-side: POST /v1/commission is
 * require_roles(DEDUKE_ADMIN) only (AGENTS.md: never rely on hiding UI
 * elements client-side).
 */
export default async function CommissionConfigPage() {
  const session = await getAdminSession();

  if (!session) {
    return (
      <main className="p-lg">
        <h1 className="font-heading text-xl font-semibold">Commission rate configuration</h1>
        <p className="mt-sm text-text-secondary">
          Sign in with a De-Duke Staff or Admin account to view commission rates.
        </p>
      </main>
    );
  }

  return (
    <main className="p-lg">
      <h1 className="font-heading text-xl font-semibold">Commission rate configuration</h1>
      <p className="mt-xs text-text-secondary">
        {session.role === "deduke_admin"
          ? "View and update commission rates per transaction type."
          : "Read-only. Only Admin accounts can change commission rates."}
      </p>
      <div className="mt-lg">
        <CommissionConfigClient isAdmin={session.role === "deduke_admin"} />
      </div>
    </main>
  );
}
