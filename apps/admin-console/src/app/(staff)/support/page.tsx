import { getAdminSession } from "@/lib/auth";
import { SupportInboxClient } from "@/components/support/SupportInboxClient";

/** screens.md Screen 26: Admin General Support Inbox -- FEAT-029. */
export default async function SupportPage() {
  const session = await getAdminSession();

  if (!session) {
    return (
      <main className="p-lg">
        <h1 className="font-heading text-xl font-semibold">Support</h1>
        <p className="mt-sm text-text-secondary">
          Sign in with a De-Duke Staff or Admin account to view the support inbox.
        </p>
      </main>
    );
  }

  return (
    <main className="p-lg">
      <h1 className="font-heading text-xl font-semibold">Support</h1>
      <p className="mt-xs text-text-secondary">
        General support conversations not tied to a specific listing.
      </p>
      <div className="mt-lg">
        <SupportInboxClient currentUserId={session.userId} />
      </div>
    </main>
  );
}
