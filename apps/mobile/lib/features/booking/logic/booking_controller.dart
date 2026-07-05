/// State machine for the booking confirmation screen (FEAT-032).
/// Screens/screens.md states covered: loading, submitting, error, held
/// (with live countdown), expired.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/booking_api.dart';

enum BookingScreenStatus { idle, submitting, held, expired, error }

class BookingController extends ChangeNotifier {
  BookingController(this._api);

  final BookingApi _api;
  Timer? _ticker;

  BookingScreenStatus status = BookingScreenStatus.idle;
  BookingHold? hold;
  String? errorMessage;
  Duration timeRemaining = Duration.zero;

  Future<void> confirmBooking({
    required String listingId,
    DateTime? checkInDate,
    DateTime? checkOutDate,
  }) async {
    status = BookingScreenStatus.submitting;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await _api.confirmBooking(
        listingId: listingId,
        checkInDate: checkInDate,
        checkOutDate: checkOutDate,
      );
      hold = result;
      status = BookingScreenStatus.held;
      _startCountdown();
    } on BookingApiException catch (e) {
      errorMessage = e.message;
      status = BookingScreenStatus.error;
    }
    notifyListeners();
  }

  void _startCountdown() {
    _ticker?.cancel();
    _tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final current = hold;
    if (current == null) return;
    final remaining =
        current.holdExpiresAt.toUtc().difference(DateTime.now().toUtc());
    if (remaining.isNegative) {
      timeRemaining = Duration.zero;
      status = BookingScreenStatus.expired;
      _ticker?.cancel();
    } else {
      timeRemaining = remaining;
    }
    notifyListeners();
  }

  /// Restarts the whole confirm flow after a Hold Expired state, per
  /// screens.md's "Hold Expired state + restart" requirement.
  void restart() {
    _ticker?.cancel();
    hold = null;
    errorMessage = null;
    timeRemaining = Duration.zero;
    status = BookingScreenStatus.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
