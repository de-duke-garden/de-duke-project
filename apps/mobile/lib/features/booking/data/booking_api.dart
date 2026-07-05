/// Data access for FEAT-032 (Booking Hold & Confirm-Before-Pay).
/// All network access for this feature goes through here -- screens/logic
/// never call Dio directly, per architecture.md's layered client structure.
import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';

class BookingHold {
  BookingHold({
    required this.transactionId,
    required this.listingId,
    required this.status,
    required this.grossAmount,
    required this.holdExpiresAt,
    this.possessionStart,
    this.possessionEnd,
  });

  factory BookingHold.fromJson(Map<String, dynamic> json) => BookingHold(
        transactionId: json['transaction_id'] as String,
        listingId: json['listing_id'] as String,
        status: json['status'] as String,
        grossAmount: (json['gross_amount'] as num).toDouble(),
        holdExpiresAt: DateTime.parse(json['hold_expires_at'] as String),
        possessionStart: json['possession_period_start_date'] != null
            ? DateTime.parse(json['possession_period_start_date'] as String)
            : null,
        possessionEnd: json['possession_period_end_date'] != null
            ? DateTime.parse(json['possession_period_end_date'] as String)
            : null,
      );

  final String transactionId;
  final String listingId;
  final String status;
  final double grossAmount;
  final DateTime holdExpiresAt;
  final DateTime? possessionStart;
  final DateTime? possessionEnd;

  bool get isExpired =>
      status == 'expired' ||
      DateTime.now().toUtc().isAfter(holdExpiresAt.toUtc());
}

class BookingApiException implements Exception {
  BookingApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
}

class BookingApi {
  BookingApi(this._client);
  final ApiClient _client;

  Future<BookingHold> confirmBooking({
    required String listingId,
    DateTime? checkInDate,
    DateTime? checkOutDate,
  }) async {
    try {
      final response = await _client.dio.post('/v1/bookings/confirm', data: {
        'listing_id': listingId,
        if (checkInDate != null) 'check_in_date': checkInDate.toIso8601String(),
        if (checkOutDate != null)
          'check_out_date': checkOutDate.toIso8601String(),
      });
      return BookingHold.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw BookingApiException(
        _messageFor(e),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<BookingHold> getBooking(String transactionId) async {
    try {
      final response = await _client.dio.get('/v1/bookings/$transactionId');
      return BookingHold.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw BookingApiException(_messageFor(e),
          statusCode: e.response?.statusCode);
    }
  }

  String _messageFor(DioException e) {
    final status = e.response?.statusCode;
    final detail =
        e.response?.data is Map ? (e.response?.data as Map)['detail'] : null;
    if (detail is String) return detail;
    if (status == 409) return 'These dates are no longer available.';
    if (status == 404) return 'This listing could not be found.';
    return 'Something went wrong. Please check your connection and try again.';
  }
}
