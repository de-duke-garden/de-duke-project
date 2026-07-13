/**
 * One-shot Firestore aggregate counts for the Admin Home / Overview
 * screen (screens.md Screen 22). Uses `getCountFromServer` -- a server-side
 * aggregation query -- rather than subscribing to the full collection with
 * `onSnapshot`, since the Home screen only ever needs a number, not the
 * documents themselves (unlike Chat Oversight / Support Inbox, which do
 * need the live document set and use `onSnapshot`).
 */

import { collection, getCountFromServer, query, where, type Firestore } from "firebase/firestore";

/** General Support Inbox unresolved count -- support_conversations whose
 * status has not reached "resolved" (chat_service.py defaults new support
 * conversations to status "open"; SupportInboxClient's own filter treats
 * anything other than "resolved" as needing attention). */
export async function getSupportUnresolvedCount(db: Firestore): Promise<number> {
  const q = query(collection(db, "support_conversations"), where("status", "!=", "resolved"));
  const snapshot = await getCountFromServer(q);
  return snapshot.data().count;
}

/** Conversations Needing Staff Attention -- client/property-management
 * conversations with no staff member assigned yet (chat_service.py creates
 * every conversation with `assignedStaffId: null`; there is no separate
 * "flagged" field in the current Firestore schema, so an unassigned
 * conversation is the closest available proxy for "needs staff attention".
 * Flagged as an assumption -- revisit if/when a dedicated flag field ships). */
export async function getConversationsNeedingAttentionCount(db: Firestore): Promise<number> {
  const q = query(collection(db, "conversations"), where("assignedStaffId", "==", null));
  const snapshot = await getCountFromServer(q);
  return snapshot.data().count;
}
