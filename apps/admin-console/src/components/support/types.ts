// Mirrors apps/backend/app/firestore_models.py's SupportConversation --
// FEAT-029. ChatMessage (support/../chat/types.ts) is reused as-is since
// the message document shape is identical in both collections.

export interface SupportConversation {
  id: string;
  userId: string;
  assignedStaffId: string | null;
  // open | resolved
  status: string;
  lastMessageAt: number | null;
  createdAt: number | null;
}
