/// Repository wrapping the Backend API Service's FEAT-020 share endpoints
/// (app/api/v1/share.py). Screen 17 (Generate) is the only mobile consumer --
/// Screen 18 (External View) is a web-only, unauthenticated page rendered by
/// the admin-console's public `/s/:token` route, not this app.
library;

import '../../../core/api/api_client.dart';
import 'share_models.dart';

class ShareRepository {
  ShareRepository(this._apiClient);

  final ApiClient _apiClient;

  /// POST /v1/listings/:id/share -- auth required (enforced server-side).
  Future<ShareLink> generateShareLink(String listingId) async {
    final response =
        await _apiClient.dio.post('/v1/listings/$listingId/share');
    return ShareLink.fromJson(response.data as Map<String, dynamic>);
  }

  /// DELETE /v1/listings/:id/share/:token -- only the originating user may
  /// revoke (server enforces ownership; a 403 here means this client's own
  /// session isn't the token's creator, which shouldn't happen in normal use
  /// since a link is only ever surfaced to its own creator here).
  Future<void> revokeShareLink(String listingId, String shareToken) async {
    await _apiClient.dio.delete('/v1/listings/$listingId/share/$shareToken');
  }
}
