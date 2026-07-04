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

  factory ChatTokenResult.fromJson(Map<String, dynamic> json) => ChatTokenResult(
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
  /// Firestore session, scoped by the `role` custom claim.
  Future<ChatTokenResult> fetchChatToken() async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>('/v1/chat/token');
    return ChatTokenResult.fromJson(response.data!);
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
}
