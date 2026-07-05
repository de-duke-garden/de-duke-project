import { getAdminSession } from "@/lib/auth";
import { HostVerificationQueueClient } from "@/components/host-verification/HostVerificationQueueClient";

/** screens.md Screen 27: Admin Host Verification Review -- FEAT-002.
 *
 * Role gate happens here (server-rendered) AND is re-checked by the
 * Backend API Service on every /v1/host-accounts/admin/* call (AGENTS.md:
 * never rely on hiding UI elements client-side).
 */
export default async function HostVerificationPage() {
  const session = await getAdminSession();

  if (!session) {
    return (
      <main className="p-lg">
        <h1 className="font-heading text-xl font-semibold">Host verification review</h1>
        <p className="mt-sm text-text-secondary">
          Sign in with a De-Duke Staff or Admin account to review host verification submissions.
        </p>
      </main>
    );
  }

  return (
    <main className="p-lg">
      <h1 className="font-heading text-xl font-semibold">Host verification review</h1>
      <p className="mt-xs text-text-secondary">
        Submissions awaiting review. Click a row to inspect documents and verify or reject.
      </p>
      <div className="mt-lg">
        <HostVerificationQueueClient />
      </div>
    </main>
  );
}
