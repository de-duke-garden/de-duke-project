/// Repository wrapping the Backend API Service's reporting endpoints --
/// FEAT-009 (In-App Reporting). Screens depend on this, never on
/// Dio/ApiClient directly, matching listing_repository.dart's convention.
library;

import '../../../core/api/api_client.dart';

/// fake | scam | incorrect_info | other -- mirrors
/// app/models/report.py's REPORT_REASONS.
enum ReportReason { fake, scam, incorrectInfo, other }

extension ReportReasonJson on ReportReason {
  String get wireValue => switch (this) {
        ReportReason.fake => 'fake',
        ReportReason.scam => 'scam',
        ReportReason.incorrectInfo => 'incorrect_info',
        ReportReason.other => 'other',
      };

  String get label => switch (this) {
        ReportReason.fake => 'Fake listing',
        ReportReason.scam => 'Scam or fraud',
        ReportReason.incorrectInfo => 'Incorrect information',
        ReportReason.other => 'Other',
      };
}

class ReportRepository {
  ReportRepository(this._apiClient);

  final ApiClient _apiClient;

  /// screens.md Screen 6: POST /listings/:id/report.
  Future<void> reportListing(
    String listingId, {
    required ReportReason reason,
    String? detail,
  }) async {
    await _apiClient.dio.post(
      '/v1/listings/$listingId/report',
      data: {
        'reason': reason.wireValue,
        if (detail != null && detail.trim().isNotEmpty) 'detail': detail.trim(),
      },
    );
  }

  /// Chat Thread screen's report-conversation action:
  /// POST /conversations/:id/report.
  Future<void> reportConversation(
    String conversationId, {
    required ReportReason reason,
    String? detail,
  }) async {
    await _apiClient.dio.post(
      '/v1/conversations/$conversationId/report',
      data: {
        'reason': reason.wireValue,
        if (detail != null && detail.trim().isNotEmpty) 'detail': detail.trim(),
      },
    );
  }
}
