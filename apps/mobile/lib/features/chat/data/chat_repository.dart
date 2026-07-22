/// Direct-to-Firestore chat data access -- FEAT-010. Real-time message
/// send/receive/listening is client-side per the architecture decision:
/// the backend only issues auth tokens + creates conversations, it never
/// proxies message traffic.
///
/// Firestore's own offline cache + write-queue (enabled by default on
/// mobile) is relied on for offline handling -- messages sent while offline
/// queue locally and sync automatically on reconnect; no custom retry/queue
/// logic is implemented here.
import 'dart:async';

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

  /// Must be called before any of the stream/send methods below --
  /// Firestore security rules (apps/backend/firestore.rules) reject
  /// unauthenticated requests, and (for the common case below) requests
  /// missing the `deduke_user_id`/`role` custom claims those rules key
  /// off of.
  ///
  /// Post-FEAT-001, the mobile app's only users are consumer roles
  /// (Guest, Host, Agency), and they're already
  /// signed into a REAL Firebase Authentication session (Google/email/
  /// phone) by the time they're logged into De-Duke at all -- there's no
  /// separate chat-specific identity to sign into. What that real
  /// session is still missing is the `deduke_user_id`/`role` custom
  /// claims firestore.rules requires (a brand-new sign-in never carried
  /// them, and a role change, FEAT-003, can make them stale) -- so this
  /// asks the backend to (re)apply them via `POST /v1/chat/sync-claims`
  /// every time chat is entered (cheap, idempotent, self-healing), then
  /// force-refreshes the cached ID token: Firebase's SDK doesn't pick up
  /// a custom-claims change until the token is reminted, which otherwise
  /// wouldn't happen on its own for up to an hour.
  ///
  /// The `currentUser == null` branch is a defensive fallback only --
  /// shouldn't be reachable in practice (a consumer can't be logged into
  /// De-Duke without an active Firebase session), kept for the case
  /// where the Firebase SDK's local session was somehow cleared out from
  /// under the (still-valid) De-Duke session.
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

  /// Live stream of a conversation's most recent message, backing each
  /// Chat Inbox row's preview text/unread indicator. Confirmed real gap
  /// this replaces: the inbox previously resolved this via a one-time
  /// `getLastMessage().then(...)` fetch inside a `FutureBuilder`, which
  /// only ever re-ran when the *conversation list itself* rebuilt (i.e.
  /// when `lastMessageAt` changed). Marking a message read doesn't touch
  /// `lastMessageAt`, so returning to the inbox after reading a thread
  /// left the unread dot/bold preview stuck stale until some unrelated new
  /// message arrived anywhere in the list. Streaming the same query
  /// directly means a row's preview and unread state update the instant
  /// either a new message arrives or its delivery status changes -- true
  /// real-time, not "real-time until the row stops rebuilding".
  Stream<ChatMessage?> watchLastMessage(String conversationId) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty
            ? null
            : ChatMessage.fromFirestore(snap.docs.first));
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

    // FEAT-022: triggers a push to the OTHER participant -- see
    // ChatApi.notifyNewMessage's docstring for why this is a separate
    // backend call rather than something Firestore itself can trigger in
    // this stack. Fire-and-forget: a failure here must never fail the
    // message send itself (the message is already durably written above),
    // and a missed push notification is not worth surfacing as a chat
    // error to the sender.
    unawaited(_chatApi.notifyNewMessage(conversationId).catchError((_) {}));
  }

  Future<void> markMessageRead(String conversationId, String messageId) {
    return _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .update({'deliveryStatus': 'read'});
  }
}
