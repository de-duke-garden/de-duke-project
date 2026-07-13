/// FEAT-032 -- Booking Confirmation screen (screens.md): summary, explicit
/// confirm action, live hold countdown, Hold Expired state + restart.
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/badge_pop.dart';
import '../data/booking_api.dart';
import '../logic/booking_controller.dart';

class BookingConfirmationScreen extends StatefulWidget {
  const BookingConfirmationScreen({
    super.key,
    required this.controller,
    required this.listingId,
    required this.listingTitle,
    required this.priceSummary,
    this.checkInDate,
    this.checkOutDate,
    required this.onProceedToCheckout,
  });

  final BookingController controller;
  final String listingId;
  final String listingTitle;
  final String priceSummary;
  final DateTime? checkInDate;
  final DateTime? checkOutDate;
  final void Function(BookingHold hold) onProceedToCheckout;

  @override
  State<BookingConfirmationScreen> createState() =>
      _BookingConfirmationScreenState();
}

class _BookingConfirmationScreenState extends State<BookingConfirmationScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm your booking')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _buildBody(controller),
      ),
    );
  }

  Widget _buildBody(BookingController controller) {
    // Screen 6b Modernization Notes: Default -> Hold Active is a
    // purposeful `duration-normal` in-place shift (form recedes, countdown
    // settles in) -- deliberately calm, no list-stagger/celebratory-
    // sequence on this time-pressured screen.
    return AnimatedSwitcher(
      duration: AppDurations.normal,
      switchInCurve: AppCurves.easeOutSmooth,
      switchOutCurve: AppCurves.easeOutSmooth,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
            sizeFactor: animation, alignment: Alignment.topCenter, child: child),
      ),
      child: KeyedSubtree(
        key: ValueKey(controller.status),
        child: switch (controller.status) {
          BookingScreenStatus.idle => _buildSummary(controller, submitting: false),
          BookingScreenStatus.submitting =>
            _buildSummary(controller, submitting: true),
          BookingScreenStatus.held => _buildHeld(controller),
          BookingScreenStatus.expired => _buildExpired(),
          BookingScreenStatus.error => _buildError(controller),
        },
      ),
    );
  }

  Widget _buildSummary(BookingController controller,
      {required bool submitting}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.listingTitle,
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(widget.priceSummary,
            style: AppTypography.statDisplay.copyWith(color: AppColors.primary)),
        if (widget.checkInDate != null && widget.checkOutDate != null) ...[
          const SizedBox(height: 8),
          Text(
            '${_fmt(widget.checkInDate!)} -> ${_fmt(widget.checkOutDate!)}',
          ),
        ],
        const Spacer(),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: submitting
                ? null
                : () => controller.confirmBooking(
                      listingId: widget.listingId,
                      checkInDate: widget.checkInDate,
                      checkOutDate: widget.checkOutDate,
                    ),
            child: submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Confirm booking'),
          ),
        ),
      ],
    );
  }

  Widget _buildHeld(BookingController controller) {
    final hold = controller.hold!;
    final remaining = controller.timeRemaining;
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    // `warning` as the countdown nears expiry (branding.md semantic status
    // colors, Screen 6b Modernization Notes), always paired with icon+text.
    final nearingExpiry = remaining.inSeconds <= 120;
    final statusColor = nearingExpiry ? AppColors.error : AppColors.warning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // `badge-pop` on the countdown timer settling in when a hold is
        // created (Screen 6b Modernization Notes) -- keyed once per hold
        // so it pops on arrival, not on every tick.
        BadgePop(
          triggerKey: hold.transactionId,
          child: Row(
            children: [
              Icon(Icons.lock_clock, color: statusColor),
              const SizedBox(width: 8),
              Text(
                'Hold active -- ${minutes}m ${seconds.toString().padLeft(2, '0')}s remaining',
                style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Amount due: NGN ${hold.grossAmount.toStringAsFixed(2)}'),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () => widget.onProceedToCheckout(hold),
            child: const Text('Proceed to checkout'),
          ),
        ),
      ],
    );
  }

  Widget _buildExpired() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.timer_off, color: AppColors.error, size: 48),
        const SizedBox(height: 16),
        const Text(
          'Your hold expired',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error),
        ),
        const SizedBox(height: 8),
        const Text('Someone else may now be able to book these dates.'),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: widget.controller.restart,
            child: const Text('Start again'),
          ),
        ),
      ],
    );
  }

  Widget _buildError(BookingController controller) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, color: AppColors.error, size: 48),
        const SizedBox(height: 16),
        Text(
          controller.errorMessage ?? 'Something went wrong.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: controller.restart,
            child: const Text('Try again'),
          ),
        ),
      ],
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
