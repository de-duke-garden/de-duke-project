import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:de_duke_mobile/features/booking/data/booking_api.dart';
import 'package:de_duke_mobile/features/booking/logic/booking_controller.dart';

class MockBookingApi extends Mock implements BookingApi {}

void main() {
  late MockBookingApi api;
  late BookingController controller;

  setUp(() {
    api = MockBookingApi();
    controller = BookingController(api);
  });

  tearDown(() {
    controller.dispose();
  });

  test('starts in the idle state with no hold', () {
    expect(controller.status, BookingScreenStatus.idle);
    expect(controller.hold, isNull);
  });

  test('confirmBooking transitions idle -> submitting -> held on success',
      () async {
    final hold = BookingHold(
      transactionId: 'txn-1',
      listingId: 'listing-1',
      status: 'held',
      grossAmount: 45000,
      holdExpiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
    );
    when(() => api.confirmBooking(
          listingId: any(named: 'listingId'),
          checkInDate: any(named: 'checkInDate'),
          checkOutDate: any(named: 'checkOutDate'),
        )).thenAnswer((_) async => hold);

    await controller.confirmBooking(listingId: 'listing-1');

    expect(controller.status, BookingScreenStatus.held);
    expect(controller.hold, hold);
    expect(controller.errorMessage, isNull);
  });

  test('confirmBooking transitions to error state on BookingApiException',
      () async {
    when(() => api.confirmBooking(
              listingId: any(named: 'listingId'),
              checkInDate: any(named: 'checkInDate'),
              checkOutDate: any(named: 'checkOutDate'),
            ))
        .thenThrow(BookingApiException('These dates are no longer available.',
            statusCode: 409));

    await controller.confirmBooking(listingId: 'listing-1');

    expect(controller.status, BookingScreenStatus.error);
    expect(controller.errorMessage, 'These dates are no longer available.');
    expect(controller.hold, isNull);
  });

  test('a hold whose holdExpiresAt is already in the past ticks to expired',
      () async {
    final hold = BookingHold(
      transactionId: 'txn-2',
      listingId: 'listing-1',
      status: 'held',
      grossAmount: 45000,
      // Already expired the instant it's created.
      holdExpiresAt:
          DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
    );
    when(() => api.confirmBooking(
          listingId: any(named: 'listingId'),
          checkInDate: any(named: 'checkInDate'),
          checkOutDate: any(named: 'checkOutDate'),
        )).thenAnswer((_) async => hold);

    await controller.confirmBooking(listingId: 'listing-1');

    // The countdown ticks immediately on hold creation (see
    // BookingController._startCountdown -> _tick()), so an already-expired
    // hold should be reflected as expired without waiting for the timer.
    expect(controller.status, BookingScreenStatus.expired);
  });

  test('restart clears hold/status back to idle after expiry', () async {
    final hold = BookingHold(
      transactionId: 'txn-3',
      listingId: 'listing-1',
      status: 'held',
      grossAmount: 45000,
      holdExpiresAt:
          DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
    );
    when(() => api.confirmBooking(
          listingId: any(named: 'listingId'),
          checkInDate: any(named: 'checkInDate'),
          checkOutDate: any(named: 'checkOutDate'),
        )).thenAnswer((_) async => hold);

    await controller.confirmBooking(listingId: 'listing-1');
    expect(controller.status, BookingScreenStatus.expired);

    controller.restart();

    expect(controller.status, BookingScreenStatus.idle);
    expect(controller.hold, isNull);
    expect(controller.errorMessage, isNull);
  });
}
