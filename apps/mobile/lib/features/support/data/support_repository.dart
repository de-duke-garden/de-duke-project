/// Direct-to-Firestore support chat data access -- FEAT-029. Mirrors
/// chat_repository.dart's design exactly (backend only issues auth
/// tokens + creates the conversation document; message read/write is
/// client-side against Firestore's `support_conversations` collection).
/// Reuses ChatMessage/ChatDeliveryStatus from the chat feature -- message
/// documents have the identical shape in both collections.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

import '../../chat/data/chat_api.dart';
import '../../chat/data/chat_models.dart';
import 'support_api.dart';

class SupportConversation {
  const SupportConversation({
    required this.id,
    required this.userId,
    required this.assignedStaffId,
    required this.status,
    required this.lastMessageAt,
    required this.createdAt,
  });

  factory SupportConversation.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return SupportConversation(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      assignedStaffId: data['assignedStaffId'] as String?,
      status: data['status'] as String? ?? 'open',
      lastMessageAt:
          (data['lastMessageAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  final String id;
  final String userId;
  final String? assignedStaffId;
  final String status;
  final DateTime lastMessageAt;
  final DateTime createdAt;
}

class SupportRepository {
  SupportRepository({
    required SupportApi supportApi,
    required ChatApi chatApi,
    FirebaseFirestore? firestore,
    fb_auth.FirebaseAuth? firebaseAuth,
  })  : _supportApi = supportApi,
        _chatApi = chatApi,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _firebaseAuth = firebaseAuth ?? fb_auth.FirebaseAuth.instance;

  final SupportApi _supportApi;
  final ChatApi _chatApi;
  final FirebaseFirestore _firestore;
  final fb_auth.FirebaseAuth _firebaseAuth;

  /// Support conversations are gated by the exact same
  /// `deduke_user_id`/`role` custom claims as regular chat (just a
  /// different Firestore collection/match block in firestore.rules) --
  /// so this reuses ChatApi.syncChatClaims/fetchChatToken rather than
  /// duplicating the FEAT-001/FEAT-010 reconciliation logic. See
  /// ChatRepository.ensureSignedIn's docstring for the full "why".
  Future<void> ensureSignedIn() async {
    if (_firebaseAuth.currentUser == null) {
      final tokenResult = await _chatApi.fetchChatToken();
      await _firebaseAuth
          .signInWithCustomToken(tokenResult.firebaseCustomToken);
      return;
    }
    await _chatApi.syncChatClaims();
    await _firebaseAuth.currentUser?.getIdToken(true);
  }

  /// Idempotent -- returns the caller's existing conversation id if one
  /// already exists, otherwise creates it.
  Future<String> getOrCreateConversation() async {
    final result = await _supportApi.getOrCreateConversation();
    return result.id;
  }

  Stream<SupportConversation?> watchConversation(String conversationId) {
    return _firestore
        .collection('support_conversations')
        .doc(conversationId)
        .snapshots()
        .map((doc) =>
            doc.exists ? SupportConversation.fromFirestore(doc) : null);
  }

  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    return _firestore
        .collection('support_conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('sentAt')
        .snapshots(includeMetadataChanges: true)
        .map((snap) => snap.docs.map(ChatMessage.fromFirestore).toList());
  }

  /// Writes a new message doc and reopens the conversation if it had been
  /// marked resolved (screens.md Screen 26 edge case: "User sends a
  /// follow-up message after a conversation was marked resolved ->
  /// conversation automatically reopens").
  Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String body,
  }) async {
    final conversationRef =
        _firestore.collection('support_conversations').doc(conversationId);
    final messageRef = conversationRef.collection('messages').doc();

    final batch = _firestore.batch();
    batch.set(messageRef, {
      'senderId': senderId,
      'senderRole': 'client',
      'messageType': 'text',
      'body': body,
      'deliveryStatus': 'sent',
      'sentAt': FieldValue.serverTimestamp(),
    });
    batch.update(conversationRef, {
      'lastMessageAt': FieldValue.serverTimestamp(),
      'status': 'open',
    });
    await batch.commit();

    // FEAT-022: fire-and-forget push trigger, same rationale as
    // ChatRepository.sendMessage -- a missed push must never fail the
    // (already durably written) message send itself.
    unawaited(_supportApi.notifyNewMessage(conversationId).catchError((_) {}));
  }
}
