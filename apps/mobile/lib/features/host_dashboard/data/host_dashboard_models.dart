/// Mirrors apps/backend/app/schemas/host_dashboard.py -- keep field
/// names in sync with that file if either side changes.
library;

class HostDashboardListingItem {
  const HostDashboardListingItem({
    required this.id,
    required this.title,
    required this.listingType,
    required this.status,
    required this.statusReason,
    required this.viewCount,
    required this.inquiryCount,
    required this.primaryImageUrl,
    required this.isStale,
  });

  final String id;
  final String title;
  final String listingType;
  final String status;
  final String? statusReason;
  final int viewCount;
  final int inquiryCount;
  final String? primaryImageUrl;
  final bool isStale;

  factory HostDashboardListingItem.fromJson(Map<String, dynamic> json) {
    return HostDashboardListingItem(
      id: json['id'] as String,
      title: json['title'] as String,
      listingType: json['listing_type'] as String,
      status: json['status'] as String,
      statusReason: json['status_reason'] as String?,
      viewCount: json['view_count'] as int,
      inquiryCount: json['inquiry_count'] as int,
      primaryImageUrl: json['primary_image_url'] as String?,
      isStale: json['is_stale'] as bool,
    );
  }
}
