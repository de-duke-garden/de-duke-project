/// Data models for FEAT-020 (Shareable Listing Summary for Internal
/// Approval), mirroring apps/backend/app/schemas/share.py.
library;

/// Response of POST /v1/listings/:id/share -- Screen 17's "Generated" state.
class ShareLink {
  const ShareLink({
    required this.shareToken,
    required this.listingId,
    this.expiresAt,
  });

  final String shareToken;
  final String listingId;
  final String? expiresAt;

  factory ShareLink.fromJson(Map<String, dynamic> json) => ShareLink(
        shareToken: json['share_token'] as String,
        listingId: json['listing_id'] as String,
        expiresAt: json['expires_at'] as String?,
      );
}
