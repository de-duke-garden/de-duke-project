export interface ChatConversation {
  id: string;
  listingId: string;
  clientId: string;
  propertyManagementId: string;
  assignedStaffId: string | null;
  lastMessageAt: number | null;
  createdAt: number | null;
}

export interface ChatMessage {
  id: string;
  conversationId: string;
  senderId: string | null;
  // client | property_management | deduke_staff | null (system messages)
  senderRole: string | null;
  // text | system
  messageType: string;
  body: string;
  // sending | sent | delivered | read | failed
  deliveryStatus: string;
  sentAt: number | null;
}
