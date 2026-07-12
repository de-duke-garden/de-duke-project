import { getAdminSession } from "@/lib/auth";
import { DisputesClient } from "@/components/disputes/DisputesClient";

/** screens.md Screen 24: Admin Dispute & Refund Management -- FEAT-026.
 *
 * Role gate happens here (server-rendered) AND is re-checked by the
 * Backend API Service on every /v1/disputes/* call (AGENTS.md: never rely
 * on hiding UI elements client-side), same pattern as the Moderation
 * Queue page.
 */
export default async function DisputesPage() {
  const session = await getAdminSession();

  if (!session) {
    return (
      <main className="p-lg">
        <h1 className="font-heading text-xl font-semibold">Disputes</h1>
        <p className="mt-sm text-text-secondary">
          Sign in with a De-Duke Staff or Admin account to review disputes.
        </p>
      </main>
    );
  }

  return (
    <main className="p-lg">
      <h1 className="font-heading text-xl font-semibold">Disputes</h1>
      <p className="mt-xs text-text-secondary">
        Payment disputes and refund requests raised against real transactions.
      </p>
      <div className="mt-lg">
        <DisputesClient />
      </div>
    </main>
  );
}
