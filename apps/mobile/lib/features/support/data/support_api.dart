/// Backend-facing support API calls -- FEAT-029. Mirrors chat_api.dart's
/// shape exactly: the backend only creates the conversation document and
/// relays a push-notify trigger. Sending/receiving messages happens
/// directly against Firestore (see support_repository.dart).
import '../../../core/api/api_client.dart';

class SupportConversationResult {
  const SupportConversationResult({
    required this.id,
    required this.status,
  });

  factory SupportConversationResult.fromJson(Map<String, dynamic> json) =>
      SupportConversationResult(
        id: json['id'] as String,
        status: json['status'] as String,
      );

  final String id;
  final String status;
}

class SupportApi {
  SupportApi(this._apiClient);

  final ApiClient _apiClient;

  /// POST /v1/support/conversations -- idempotent get-or-create; there is
  /// at most one support conversation per user (backend enforces this).
  Future<SupportConversationResult> getOrCreateConversation() async {
    final response = await _apiClient.dio
        .post<Map<String, dynamic>>('/v1/support/conversations');
    return SupportConversationResult.fromJson(response.data!);
  }

  /// POST /v1/support/conversations/{id}/notify -- same rationale as
  /// ChatApi.notifyNewMessage (backend never observes the Firestore write
  /// itself).
  Future<void> notifyNewMessage(String conversationId) {
    return _apiClient.dio
        .post('/v1/support/conversations/$conversationId/notify');
  }
}
