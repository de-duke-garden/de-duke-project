/// Repository wrapping GET/POST/PATCH /v1/agency/* (FEAT-012, FEAT-019).
/// Screens depend on this, never on Dio directly -- same shape as
/// host_dashboard_repository.dart.
library;

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import 'agency_models.dart';

class AgencyException implements Exception {
  AgencyException(this.message,
      {this.isOffline = false, this.isConflict = false});

  final String message;

  /// Drives a screen's `Offline` state (connection-level failure) as
  /// distinct from a normal `Error` state.
  final bool isOffline;

  /// Screen 15 Edge Case: "Two admins attempt to assign the same lead
  /// simultaneously" -- the loser gets a 409, surfaced distinctly so the
  /// screen can show "assigned by someone else" instead of a generic error.
  final bool isConflict;

  @override
  String toString() => message;
}

class AgencyRepository {
  AgencyRepository(this._apiClient);

  final ApiClient _apiClient;

  AgencyException _toException(DioException e, String fallback) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return AgencyException('offline', isOffline: true);
    }
    final data = e.response?.data;
    final detail = (data is Map && data['detail'] is String)
        ? data['detail'] as String
        : fallback;
    return AgencyException(detail, isConflict: e.response?.statusCode == 409);
  }

  // -- Screen 13: Agency Dashboard ------------------------------------------

  Future<AgencySummary> getSummary() async {
    try {
      final response = await _apiClient.dio.get('/v1/agency/summary');
      return AgencySummary.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e, "Couldn't load your agency summary.");
    }
  }

  // -- Screen 14: Portfolio List View ----------------------------------------

  Future<List<AgencyListingItem>> getListings({String? status}) async {
    try {
      final response = await _apiClient.dio.get(
        '/v1/agency/listings',
        queryParameters: {if (status != null) 'status': status},
      );
      return (response.data as List)
          .map((e) => AgencyListingItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _toException(e, "Couldn't load your portfolio.");
    }
  }

  // -- Team management -------------------------------------------------------

  Future<List<TeamMember>> getTeam() async {
    try {
      final response = await _apiClient.dio.get('/v1/agency/team');
      return (response.data as List)
          .map((e) => TeamMember.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _toException(e, "Couldn't load your team.");
    }
  }

  Future<TeamMember> inviteTeamMember({
    required String fullName,
    required String email,
    String agencyRole = 'agent',
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/v1/agency/team/invite',
        data: {
          'full_name': fullName,
          'email': email,
          'agency_role': agencyRole
        },
      );
      final body = response.data as Map<String, dynamic>;
      return TeamMember.fromJson(body['member'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e, "Couldn't invite this team member.");
    }
  }

  // -- Screen 15: Unassigned Leads Inbox -------------------------------------

  Future<List<Lead>> getLeads({String? status, String assignee = 'me'}) async {
    try {
      final response = await _apiClient.dio.get(
        '/v1/agency/leads',
        queryParameters: {
          if (status != null) 'status': status,
          'assignee': assignee,
        },
      );
      return (response.data as List)
          .map((e) => Lead.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _toException(e, "Couldn't load leads.");
    }
  }

  Future<Lead> assignLead(
      {required String leadId, required String assignedToId}) async {
    try {
      final response = await _apiClient.dio.patch(
        '/v1/agency/leads/$leadId/assign',
        data: {'assigned_to_id': assignedToId},
      );
      return Lead.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e, "Couldn't assign, try again");
    }
  }

  // -- Screen 16: Lead Analytics per Listing ---------------------------------

  Future<ListingAnalytics> getListingAnalytics({
    required String listingId,
    required int rangeDays,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/v1/agency/listings/$listingId/analytics',
        queryParameters: {'range': rangeDays},
      );
      return ListingAnalytics.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _toException(e, "Couldn't load this listing's analytics.");
    }
  }
}
