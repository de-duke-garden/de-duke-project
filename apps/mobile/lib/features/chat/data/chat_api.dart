/// Backend-facing chat API calls -- FEAT-010. Only two endpoints exist on
/// the backend for chat: token issuance and conversation creation. Sending/
/// receiving messages happens directly against Firestore (see
/// chat_repository.dart), never through this client.
import '../../../core/api/api_client.dart';

class ChatTokenResult {
  const ChatTokenResult({
    required this.firebaseCustomToken,
    required this.role,
    required this.expiresInSeconds,
  });

  factory ChatTokenResult.fromJson(Map<String, dynamic> json) =>
      ChatTokenResult(
        firebaseCustomToken: json['firebase_custom_token'] as String,
        role: json['role'] as String,
        expiresInSeconds: json['expires_in_seconds'] as int,
      );

  final String firebaseCustomToken;
  final String role;
  final int expiresInSeconds;
}

class ChatApi {
  ChatApi(this._apiClient);

  final ApiClient _apiClient;

  /// POST /v1/chat/token -- exchanged (client-side, via FirebaseAuth) for a
  /// Firestore session, scoped by the `role` custom claim. Legacy/
  /// defensive-fallback path only, post-FEAT-001 -- consumer accounts
  /// (the only ones the mobile app ever has) are already Firebase-
  /// authenticated for real by the time they reach chat; see
  /// [syncChatClaims] for the actual FEAT-001/FEAT-010 reconciliation
  /// path ChatRepository.ensureSignedIn() uses instead.
  Future<ChatTokenResult> fetchChatToken() async {
    final response =
        await _apiClient.dio.post<Map<String, dynamic>>('/v1/chat/token');
    return ChatTokenResult.fromJson(response.data!);
  }

  /// POST /v1/chat/sync-claims -- FEAT-001/FEAT-010 reconciliation. Asks
  /// the backend to (re)apply the `deduke_user_id`/`role` custom claims
  /// firestore.rules requires onto the caller's OWN, already-signed-in
  /// Firebase Authentication account (see app/services/chat_service.py's
  /// sync_consumer_claims docstring for the full "why"). Idempotent --
  /// safe to call every time chat is entered.
  Future<void> syncChatClaims() {
    return _apiClient.dio.post('/v1/chat/sync-claims');
  }

  /// POST /v1/chat/conversations -- server-side creation only; the returned
  /// conversation id is then used to open a Firestore listener.
  Future<String> startConversation({required String listingId}) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/v1/chat/conversations',
      data: {'listing_id': listingId},
    );
    return response.data!['id'] as String;
  }

  /// POST /v1/chat/conversations/{id}/notify -- FEAT-022. Called by the
  /// SENDING client right after its own Firestore message write succeeds
  /// (see chat_repository.dart's sendMessage) -- the backend never sees a
  /// Firestore write happen on its own, so it can't trigger a push from
  /// that write the way it can for e.g. a booking/payment event it
  /// processes itself. See app/services/chat_service.py's
  /// notify_new_message docstring for the full rationale on this design.
  Future<void> notifyNewMessage(String conversationId) {
    return _apiClient.dio.post('/v1/chat/conversations/$conversationId/notify');
  }
}
