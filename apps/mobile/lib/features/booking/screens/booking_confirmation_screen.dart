/// FEAT-032 -- Booking Confirmation screen (screens.md): summary, explicit
/// confirm action, live hold countdown, Hold Expired state + restart.
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
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
    switch (controller.status) {
      case BookingScreenStatus.idle:
        return _buildSummary(controller, submitting: false);
      case BookingScreenStatus.submitting:
        return _buildSummary(controller, submitting: true);
      case BookingScreenStatus.held:
        return _buildHeld(controller);
      case BookingScreenStatus.expired:
        return _buildExpired();
      case BookingScreenStatus.error:
        return _buildError(controller);
    }
  }

  Widget _buildSummary(BookingController controller,
      {required bool submitting}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.listingTitle,
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(widget.priceSummary, style: Theme.of(context).textTheme.bodyLarge),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.lock_clock, color: AppColors.warning),
            const SizedBox(width: 8),
            Text(
              'Hold active -- ${minutes}m ${seconds.toString().padLeft(2, '0')}s remaining',
              style: const TextStyle(
                  color: AppColors.warning, fontWeight: FontWeight.bold),
            ),
          ],
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
