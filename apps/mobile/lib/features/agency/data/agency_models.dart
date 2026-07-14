/// Mirrors apps/backend/app/schemas/agency.py -- keep field names in sync
/// with that file if either side changes. Backs screens.md Screens 13-16
/// (FEAT-012 Agent Team Inbox / Lead Assignment, FEAT-019 Lead Analytics
/// per Listing).
library;

class AgencySummary {
  const AgencySummary({
    required this.totalActiveListings,
    required this.unassignedLeadsCount,
    required this.dealsClosedThisMonth,
    required this.hasTeam,
    required this.totalViews,
    required this.totalInquiries,
    required this.totalDealsClosed,
  });

  final int totalActiveListings;
  final int unassignedLeadsCount;
  final int dealsClosedThisMonth;
  final bool hasTeam;
  // FEAT-018 AC "Portfolio view shows aggregate conversion metrics (views
  // -> inquiries -> closed deals)" -- lifetime portfolio-wide totals,
  // distinct from dealsClosedThisMonth's this-month window above.
  final int totalViews;
  final int totalInquiries;
  final int totalDealsClosed;

  factory AgencySummary.fromJson(Map<String, dynamic> json) {
    return AgencySummary(
      totalActiveListings: json['total_active_listings'] as int,
      unassignedLeadsCount: json['unassigned_leads_count'] as int,
      dealsClosedThisMonth: json['deals_closed_this_month'] as int,
      hasTeam: json['has_team'] as bool,
      totalViews: json['total_views'] as int,
      totalInquiries: json['total_inquiries'] as int,
      totalDealsClosed: json['total_deals_closed'] as int,
    );
  }
}

class AgencyListingItem {
  const AgencyListingItem({
    required this.id,
    required this.title,
    required this.listingType,
    required this.status,
    required this.assignedAgentId,
    required this.assignedAgentName,
    required this.ownerClientName,
    required this.viewCount,
    required this.inquiryCount,
  });

  final String id;
  final String title;
  final String listingType;
  final String status;
  final String? assignedAgentId;
  final String? assignedAgentName;
  // FEAT-018 AC "originating client/owner" tagging -- a free-text label an
  // agency enters (e.g. a landlord's name), not a platform account.
  final String? ownerClientName;
  final int viewCount;
  final int inquiryCount;

  factory AgencyListingItem.fromJson(Map<String, dynamic> json) {
    return AgencyListingItem(
      id: json['id'] as String,
      title: json['title'] as String,
      listingType: json['listing_type'] as String,
      status: json['status'] as String,
      assignedAgentId: json['assigned_agent_id'] as String?,
      assignedAgentName: json['assigned_agent_name'] as String?,
      ownerClientName: json['owner_client_name'] as String?,
      viewCount: json['view_count'] as int,
      inquiryCount: json['inquiry_count'] as int,
    );
  }
}

/// One listing's outcome from a `POST /agency/listings/bulk-action` call
/// (Screen 14's Bulk Action Bar) -- every listing in the batch is
/// independently succeed/fail, never all-or-nothing (see
/// agency_service.bulk_update_listing_status's docstring).
class BulkListingActionResult {
  const BulkListingActionResult({
    required this.listingId,
    required this.success,
    this.error,
  });

  final String listingId;
  final bool success;
  final String? error;

  factory BulkListingActionResult.fromJson(Map<String, dynamic> json) {
    return BulkListingActionResult(
      listingId: json['listing_id'] as String,
      success: json['success'] as bool,
      error: json['error'] as String?,
    );
  }
}

class TeamMember {
  const TeamMember({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.email,
    required this.agencyRole,
    required this.invitedAt,
    required this.joinedAt,
  });

  final String id;
  final String userId;
  final String fullName;
  final String? email;
  final String agencyRole; // admin | agent
  final DateTime invitedAt;
  final DateTime? joinedAt;

  factory TeamMember.fromJson(Map<String, dynamic> json) {
    return TeamMember(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      fullName: json['full_name'] as String,
      email: json['email'] as String?,
      agencyRole: json['agency_role'] as String,
      invitedAt: DateTime.parse(json['invited_at'] as String),
      joinedAt: json['joined_at'] != null
          ? DateTime.parse(json['joined_at'] as String)
          : null,
    );
  }
}

class Lead {
  const Lead({
    required this.id,
    required this.conversationId,
    required this.listingId,
    required this.status,
    required this.assignedToId,
    required this.assignedToName,
    required this.createdAt,
  });

  final String id;
  final String conversationId;
  final String listingId;
  final String status; // unassigned | assigned | closed | lost
  final String? assignedToId;
  final String? assignedToName;
  final DateTime createdAt;

  factory Lead.fromJson(Map<String, dynamic> json) {
    return Lead(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      listingId: json['listing_id'] as String,
      status: json['status'] as String,
      assignedToId: json['assigned_to_id'] as String?,
      assignedToName: json['assigned_to_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ListingAnalytics {
  const ListingAnalytics({
    required this.listingId,
    required this.rangeDays,
    required this.viewCount,
    required this.inquiryCount,
    required this.inquiryToViewConversionRate,
    required this.averageResponseTimeMinutes,
    required this.timeToCloseDays,
    required this.closedAt,
  });

  final String listingId;
  final int rangeDays;
  final int viewCount;
  final int inquiryCount;
  final double inquiryToViewConversionRate;
  final double? averageResponseTimeMinutes;
  final double? timeToCloseDays;
  final DateTime? closedAt;

  /// Screen 16's Empty state ("Not enough activity yet to show analytics")
  /// fires when there's been no traffic at all for the selected range.
  bool get isEmpty => viewCount == 0 && inquiryCount == 0;

  factory ListingAnalytics.fromJson(Map<String, dynamic> json) {
    return ListingAnalytics(
      listingId: json['listing_id'] as String,
      rangeDays: json['range_days'] as int,
      viewCount: json['view_count'] as int,
      inquiryCount: json['inquiry_count'] as int,
      inquiryToViewConversionRate:
          (json['inquiry_to_view_conversion_rate'] as num).toDouble(),
      averageResponseTimeMinutes:
          (json['average_response_time_minutes'] as num?)?.toDouble(),
      timeToCloseDays: (json['time_to_close_days'] as num?)?.toDouble(),
      closedAt: json['closed_at'] != null
          ? DateTime.parse(json['closed_at'] as String)
          : null,
    );
  }
}
