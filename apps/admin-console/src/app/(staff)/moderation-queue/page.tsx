import { getAdminSession } from "@/lib/auth";
import { ModerationQueueClient } from "@/components/moderation/ModerationQueueClient";

/** screens.md Screen 23: Admin Moderation Queue -- FEAT-025.
 *
 * Role gate happens here (server-rendered) AND is re-checked by the
 * Backend API Service on every /v1/moderation/* call (AGENTS.md: never rely
 * on hiding UI elements client-side). getAdminSession() is currently a
 * Foundation stub that always returns null pending Subagent 6's real auth
 * wiring (FEAT-033) -- until then this page will show the "not signed in"
 * state rather than the queue.
 */
export default async function ModerationQueuePage() {
  const session = await getAdminSession();

  if (!session) {
    return (
      <main className="p-lg">
        <h1 className="font-heading text-xl font-semibold">Moderation queue</h1>
        <p className="mt-sm text-text-secondary">
          Sign in with a De-Duke Staff or Admin account to review the moderation queue.
        </p>
      </main>
    );
  }

  return (
    <main className="p-lg">
      <h1 className="font-heading text-xl font-semibold">Moderation queue</h1>
      <p className="mt-xs text-text-secondary">
        Listings awaiting review, oldest first. Every decision requires a reason.
      </p>
      <div className="mt-lg">
        <ModerationQueueClient />
      </div>
    </main>
  );
}
