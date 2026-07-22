import { Suspense } from "react";

import { getAdminSession } from "@/lib/auth";
import { ChatOversightClient } from "@/components/chat/ChatOversightClient";

/** screens.md Screen 22: Admin Conversation Oversight (Chat Oversight
 * Module) -- FEAT-010. Any signed-in Staff or Admin can view and
 * participate in any conversation (enforced by firestore.rules, not just
 * this page).
 */
export default async function ConversationsPage() {
  const session = await getAdminSession();

  if (!session) {
    return (
      <main className="p-lg">
        <h1 className="font-heading text-xl font-semibold">Conversations</h1>
        <p className="mt-sm text-text-secondary">
          Sign in with a De-Duke Staff or Admin account to view conversations.
        </p>
      </main>
    );
  }

  return (
    <main className="p-lg">
      <h1 className="font-heading text-xl font-semibold">Conversations</h1>
      <p className="mt-xs text-text-secondary">
        Monitor and, when needed, participate in any client-property management conversation.
      </p>
      <div className="mt-lg">
        <Suspense fallback={null}>
          <ChatOversightClient currentUserId={session.userId} />
        </Suspense>
      </div>
    </main>
  );
}
