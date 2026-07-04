/// Chat data shapes -- mirrors schema.md's ChatConversation/ChatMessage
/// Firestore documents (app/firestore_models.py on the backend). These are
/// read directly from Firestore client-side; there is no backend "chat
/// messages" REST endpoint (FEAT-010: real-time is client-to-Firestore).
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.listingId,
    required this.clientId,
    required this.propertyManagementId,
    required this.assignedStaffId,
    required this.lastMessageAt,
    required this.createdAt,
  });

  factory ChatConversation.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return ChatConversation(
      id: doc.id,
      listingId: data['listingId'] as String? ?? '',
      clientId: data['clientId'] as String? ?? '',
      propertyManagementId: data['propertyManagementId'] as String? ?? '',
      assignedStaffId: data['assignedStaffId'] as String?,
      lastMessageAt: (data['lastMessageAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  final String id;
  final String listingId;
  final String clientId;
  final String propertyManagementId;
  final String? assignedStaffId;
  final DateTime lastMessageAt;
  final DateTime createdAt;
}

enum ChatDeliveryStatus { sending, sent, delivered, read, failed }

ChatDeliveryStatus _statusFromString(String? value) {
  return ChatDeliveryStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => ChatDeliveryStatus.sent,
  );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderRole,
    required this.messageType,
    required this.body,
    required this.deliveryStatus,
    required this.sentAt,
    this.pendingWrite = false,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return ChatMessage(
      id: doc.id,
      conversationId: doc.reference.parent.parent?.id ?? '',
      senderId: data['senderId'] as String?,
      senderRole: data['senderRole'] as String?,
      messageType: data['messageType'] as String? ?? 'text',
      body: data['body'] as String? ?? '',
      deliveryStatus: _statusFromString(data['deliveryStatus'] as String?),
      sentAt: (data['sentAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      // Firestore's offline write-queue: a doc created while offline has no
      // server timestamp confirmation yet -- surfaced so the UI can show a
      // "sending..." clock icon instead of a false "sent" state.
      pendingWrite: doc.metadata.hasPendingWrites,
    );
  }

  final String id;
  final String conversationId;
  final String? senderId;
  final String? senderRole;
  final String messageType;
  final String body;
  final ChatDeliveryStatus deliveryStatus;
  final DateTime sentAt;
  final bool pendingWrite;

  bool get isSystemMessage => messageType == 'system';
}
