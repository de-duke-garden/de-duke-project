/// Direct-to-Firestore chat data access -- FEAT-010. Real-time message
/// send/receive/listening is client-side per the architecture decision:
/// the backend only issues auth tokens + creates conversations, it never
/// proxies message traffic.
///
/// Firestore's own offline cache + write-queue (enabled by default on
/// mobile) is relied on for offline handling -- messages sent while offline
/// queue locally and sync automatically on reconnect; no custom retry/queue
/// logic is implemented here.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

import 'chat_api.dart';
import 'chat_models.dart';

class ChatRepository {
  ChatRepository({
    required ChatApi chatApi,
    FirebaseFirestore? firestore,
    fb_auth.FirebaseAuth? firebaseAuth,
  })  : _chatApi = chatApi,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _firebaseAuth = firebaseAuth ?? fb_auth.FirebaseAuth.instance;

  final ChatApi _chatApi;
  final FirebaseFirestore _firestore;
  final fb_auth.FirebaseAuth _firebaseAuth;

  /// Fetches a scoped custom token from the backend and exchanges it for a
  /// Firestore/Firebase Auth session. Must be called before any of the
  /// stream/send methods below -- Firestore security rules
  /// (apps/backend/firestore.rules) reject unauthenticated requests.
  Future<void> ensureSignedIn() async {
    if (_firebaseAuth.currentUser != null) return;
    final tokenResult = await _chatApi.fetchChatToken();
    await _firebaseAuth.signInWithCustomToken(tokenResult.firebaseCustomToken);
  }

  Future<String> startConversation({required String listingId}) {
    return _chatApi.startConversation(listingId: listingId);
  }

  /// One-time fetch of a single conversation -- used by the Chat Thread
  /// screen to resolve listingId/participants before subscribing to its
  /// message stream (the route only carries the conversation id).
  Future<ChatConversation?> getConversation(String conversationId) async {
    final doc =
        await _firestore.collection('conversations').doc(conversationId).get();
    if (!doc.exists) return null;
    return ChatConversation.fromFirestore(doc);
  }

  /// One-time fetch of the most recent message in a conversation, for the
  /// Chat Inbox's last-message preview / unread indicator (screens.md
  /// Screen 8) -- not a live stream, since the inbox itself already listens
  /// to the conversation list for lastMessageAt changes.
  Future<ChatMessage?> getLastMessage(String conversationId) async {
    final snap = await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return ChatMessage.fromFirestore(snap.docs.first);
  }

  /// Conversations visible to the current user -- Firestore security rules
  /// enforce the actual access boundary (client/property_management see
  /// only their own; deduke_staff sees all), this query just orders them.
  Stream<List<ChatConversation>> watchConversationsFor(String userId,
      {required bool asClient}) {
    final field = asClient ? 'clientId' : 'propertyManagementId';
    return _firestore
        .collection('conversations')
        .where(field, isEqualTo: userId)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(ChatConversation.fromFirestore).toList());
  }

  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('sentAt')
        .snapshots(includeMetadataChanges: true)
        .map((snap) => snap.docs.map(ChatMessage.fromFirestore).toList());
  }

  /// Writes a new message doc. Firestore queues this locally if offline and
  /// flushes automatically once connectivity returns -- delivery status
  /// starts at "sent" and is bumped to "delivered"/"read" by the recipient
  /// client (or staff console) as they observe the message.
  Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String senderRole,
    required String body,
  }) async {
    final conversationRef =
        _firestore.collection('conversations').doc(conversationId);
    final messageRef = conversationRef.collection('messages').doc();

    final batch = _firestore.batch();
    batch.set(messageRef, {
      'senderId': senderId,
      'senderRole': senderRole,
      'messageType': 'text',
      'body': body,
      'deliveryStatus': 'sent',
      'sentAt': FieldValue.serverTimestamp(),
    });
    batch.update(
        conversationRef, {'lastMessageAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  Future<void> markMessageRead(String conversationId, String messageId) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .update({'deliveryStatus': 'read'});
  }

  // TODO(FEAT-010/FCM): register the device's FCM token (via
  // firebase_messaging, already a dependency) against the user's profile so
  // new-message pushes can be routed while the app is backgrounded. Left
  // out of scope for this slice -- push delivery/topic wiring belongs with
  // the notifications feature.
}
