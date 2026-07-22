/// Route wrapper for screens.md Screen 6b (Confirm Booking Details).
/// BookingConfirmationScreen itself is fully parameterized by its caller
/// (title/price/dates as plain values) -- this widget resolves those from
/// the listing referenced by the route, including a lightweight date
/// selector for Shortlet/Lease listings (which need possession/stay dates)
/// before rendering it, matching screens.md's "not shown for Sale or
/// Commercial listings without a possession period" rule.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../listings/data/listing_models.dart';
import '../../listings/data/listing_repository.dart';
import '../data/booking_api.dart';
import '../logic/booking_controller.dart';
import 'booking_confirmation_screen.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({
    super.key,
    required this.listingId,
    required this.listingRepository,
    required this.bookingController,
  });

  final String listingId;
  final ListingRepository listingRepository;
  final BookingController bookingController;

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

enum _LoadState { loading, loaded, error }

class _BookingScreenState extends State<BookingScreen> {
  _LoadState _state = _LoadState.loading;
  String? _errorMessage;
  Listing? _listing;

  DateTime? _checkInDate;
  DateTime? _checkOutDate;

  // Bug fix: the date picker previously let a guest select ANY date in
  // the next year, including ones already booked (by another confirmed
  // transaction) or blocked by the host -- discovered only after they'd
  // picked dates, filled out the rest of the form, and hit a hold-
  // creation error telling them to start over. Pre-fetching the full set
  // of unavailable dates for the visible window and graying them out via
  // `selectableDayPredicate` (below) stops that dead-end before it
  // happens, using the exact same `is_listing_available` conflict logic
  // the backend enforces at hold-creation time -- this is a UX
  // pre-check, not a new source of truth; the backend still validates
  // for real (and must, to close the race between two guests picking the
  // same date concurrently) when the hold is actually created.
  Set<DateTime> _unavailableDates = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final listing =
          await widget.listingRepository.getListing(widget.listingId);
      if (!mounted) return;
      setState(() {
        _listing = listing;
        _state = _LoadState.loaded;
      });
      // Best-effort, independent of the critical listing fetch above --
      // if this fails (e.g. offline), the picker just falls back to
      // allowing every date, same as before this fix; the backend's own
      // hold-creation check is still the real, authoritative guard.
      if (_needsDateSelection) {
        unawaited(_loadUnavailableDates());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _LoadState.error;
        _errorMessage = 'Could not load this listing.';
      });
    }
  }

  Future<void> _loadUnavailableDates() async {
    try {
      final today = DateTime.now();
      final windowStart = DateTime(today.year, today.month, today.day);
      final windowEnd = windowStart.add(Duration(days: _pickerWindowDays));
      final result = await widget.listingRepository.checkAvailability(
        widget.listingId,
        start: windowStart,
        end: windowEnd,
      );
      if (!mounted) return;
      setState(() {
        _unavailableDates = result.conflictingDates
            .map(DateTime.parse)
            .map((d) => DateTime(d.year, d.month, d.day))
            .toSet();
      });
    } catch (_) {
      // Fail open (see this field's own docstring above) -- the backend
      // still enforces availability for real at hold-creation time.
    }
  }

  /// Bug fix: the date range picker's outer bound was hardcoded to 365
  /// days, but a shortlet's own `minimumStayNights` can exceed that (e.g.
  /// a long-term/annual shortlet) -- in that case there was no possible
  /// checkout date far enough out to ever satisfy the minimum stay, so
  /// the picker was unusable for that listing. The window grows to cover
  /// `minimumStayNights` plus a month of slack (so there's still real
  /// flexibility in which check-in date to pick, not just exactly one
  /// valid combination) -- never shrinks below the original 365-day
  /// default for every other listing.
  int get _pickerWindowDays {
    final minimumStayNights = _listing?.shortlet?.minimumStayNights ?? 0;
    return minimumStayNights > 365 ? minimumStayNights + 30 : 365;
  }

  bool get _needsDateSelection {
    final listing = _listing;
    if (listing == null) return false;
    if (listing.shortlet != null) return true;
    return listing.commercial != null &&
        listing.commercial!.dealType == 'lease' &&
        listing.commercial!.possessionPeriodDays != null;
  }

  String get _priceSummary {
    final listing = _listing!;
    if (listing.commercial != null) {
      final suffix = listing.commercial!.dealType == 'lease' ? ' / lease' : '';
      return '₦${listing.commercial!.price.toStringAsFixed(0)}$suffix';
    }
    return '₦${listing.shortlet!.nightlyPrice.toStringAsFixed(0)} / night';
  }

  // Raw numeric pricing, so BookingConfirmationScreen can compute and
  // render an actual nightly-rate x nights = total breakdown (FEAT-032's
  // Confirm Booking Details) rather than just echoing a pre-formatted
  // per-unit string with no total. Exactly one of these two is non-null
  // for any given listing (Commercial vs. Shortlet are mutually exclusive
  // per schema.md), matching `_priceSummary`'s own branching above.
  double? get _nightlyRate => _listing?.shortlet?.nightlyPrice;
  double? get _flatPrice => _listing?.commercial?.price;
  String? get _dealType => _listing?.commercial?.dealType;

  /// Mirrors booking_service.transaction_type_for_listing's own branching
  /// exactly -- FEAT-014's two-sided commission model looks up the
  /// buyer_fee rate by this same value, so it must match what the backend
  /// will actually compute the transaction_type as.
  String get _transactionType {
    final listing = _listing!;
    if (listing.shortlet != null) return 'shortlet_booking';
    if (listing.commercial!.dealType == 'sale') return 'sale_reservation';
    return 'lease_deposit';
  }

  Future<void> _pickDates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(Duration(days: _pickerWindowDays)),
      initialDateRange: (_checkInDate != null && _checkOutDate != null)
          ? DateTimeRange(start: _checkInDate!, end: _checkOutDate!)
          : null,
      // Grays out (disables tapping) every already-booked/blocked date --
      // see `_unavailableDates`'s own docstring for why this exists and
      // what it does/doesn't guarantee. `showDateRangePicker`'s predicate
      // signature also receives the in-progress start/end selection
      // (unlike `showDatePicker`'s single-DateTime one) -- unused here,
      // since a date's own availability doesn't depend on what else is
      // currently selected.
      selectableDayPredicate: _unavailableDates.isEmpty
          ? null
          : (day, selectedStart, selectedEnd) => !_unavailableDates.contains(
              DateTime(day.year, day.month, day.day)),
    );
    if (range == null) return;
    setState(() {
      _checkInDate = range.start;
      _checkOutDate = range.end;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _LoadState.loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Confirm your booking')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_state == _LoadState.error) {
      return Scaffold(
        appBar: AppBar(title: const Text('Confirm your booking')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_errorMessage ?? 'Something went wrong.'),
                const SizedBox(height: AppSpacing.md),
                ElevatedButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    final needsDates = _needsDateSelection;
    final datesChosen = _checkInDate != null && _checkOutDate != null;

    if (needsDates && !datesChosen) {
      return Scaffold(
        appBar: AppBar(title: const Text('Select dates')),
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_listing!.title,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(_priceSummary,
                  style: AppTypography.statDisplay.copyWith(color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: _pickDates,
                icon: const Icon(Icons.calendar_month),
                label: const Text('Choose dates'),
              ),
            ],
          ),
        ),
      );
    }

    return BookingConfirmationScreen(
      controller: widget.bookingController,
      listingId: widget.listingId,
      listingTitle: _listing!.title,
      priceSummary: _priceSummary,
      transactionType: _transactionType,
      listingRepository: widget.listingRepository,
      nightlyRate: _nightlyRate,
      flatPrice: _flatPrice,
      dealType: _dealType,
      checkInDate: _checkInDate,
      checkOutDate: _checkOutDate,
      onProceedToCheckout: (BookingHold hold) {
        context.pushNamed(
          RouteNames.checkoutTransaction,
          pathParameters: {'transactionId': hold.transactionId},
        );
      },
      // Confirmed real gap: a failed booking attempt (e.g. the dates were
      // taken by someone else in the meantime) previously just reset the
      // controller in place and re-showed THIS SAME confirm screen with
      // the SAME dates -- offering no way to actually change anything
      // before an all-but-guaranteed second failure. For date-bound
      // listings (Shortlet/Lease), clearing the chosen dates here makes
      // `build()` fall back into the Select Dates step above instead, so
      // "Try again" genuinely lets the user pick different dates rather
      // than just resubmitting the same ones.
      onTryAgain: _needsDateSelection
          ? () {
              widget.bookingController.restart();
              setState(() {
                _checkInDate = null;
                _checkOutDate = null;
              });
            }
          : null,
    );
  }
}
