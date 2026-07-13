/// Route wrapper for screens.md Screen 6b (Confirm Booking Details).
/// BookingConfirmationScreen itself is fully parameterized by its caller
/// (title/price/dates as plain values) -- this widget resolves those from
/// the listing referenced by the route, including a lightweight date
/// selector for Shortlet/Lease listings (which need possession/stay dates)
/// before rendering it, matching screens.md's "not shown for Sale or
/// Commercial listings without a possession period" rule.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';
import '../../../core/theme/app_colors.dart';
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _LoadState.error;
        _errorMessage = 'Could not load this listing.';
      });
    }
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

  Future<void> _pickDates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: (_checkInDate != null && _checkOutDate != null)
          ? DateTimeRange(start: _checkInDate!, end: _checkOutDate!)
          : null,
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
                  style: AppTypography.statDisplay.copyWith(color: AppColors.primary)),
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
      checkInDate: _checkInDate,
      checkOutDate: _checkOutDate,
      onProceedToCheckout: (BookingHold hold) {
        context.pushNamed(
          RouteNames.checkoutTransaction,
          pathParameters: {'transactionId': hold.transactionId},
        );
      },
    );
  }
}
