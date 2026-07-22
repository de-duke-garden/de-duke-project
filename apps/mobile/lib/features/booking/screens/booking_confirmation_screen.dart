/// FEAT-032 -- Booking Confirmation screen (screens.md): summary, explicit
/// confirm action, live hold countdown, Hold Expired state + restart.
///
/// Redesigned holistically (not just a bolted-on total) -- previously this
/// screen was a bare title + a single stat-display price line + a plain
/// "2026-07-22 -> 2026-07-25" text line + a button, all left-aligned with
/// no visual grouping. Now: a listing header, a "Dates" section with the
/// check-in/check-out card, a "Price details" section with an itemized
/// nightly-rate x nights = total breakdown (or a flat price/lease line for
/// Commercial listings), and a persistent bottom action bar -- the same
/// section-label + card composition already established elsewhere in this
/// app (e.g. checkout_screen.dart's own summary Card).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/badge_pop.dart';
import '../../listings/data/listing_repository.dart';
import '../data/booking_api.dart';
import '../logic/booking_controller.dart';

class BookingConfirmationScreen extends StatefulWidget {
  const BookingConfirmationScreen({
    super.key,
    required this.controller,
    required this.listingId,
    required this.listingTitle,
    required this.priceSummary,
    required this.transactionType,
    required this.listingRepository,
    this.nightlyRate,
    this.flatPrice,
    this.dealType,
    this.checkInDate,
    this.checkOutDate,
    required this.onProceedToCheckout,
    this.onTryAgain,
  });

  final BookingController controller;
  final String listingId;
  final String listingTitle;

  /// FEAT-014's two-sided commission model -- which (transaction_type,
  /// buyer_fee) rate to look up so the pre-confirm price summary below
  /// matches what the backend will actually charge. Mirrors
  /// booking_service.transaction_type_for_listing's own values
  /// ("shortlet_booking" | "lease_deposit" | "sale_reservation").
  final String transactionType;
  final ListingRepository listingRepository;

  /// Pre-formatted per-unit price (e.g. "₦50,000 / night") -- still used by
  /// booking_screen.dart's own Select Dates step; this screen now computes
  /// its own breakdown from the raw numeric fields below instead of
  /// parsing this string.
  final String priceSummary;

  /// Exactly one of [nightlyRate]/[flatPrice] is non-null for any given
  /// listing (Commercial vs. Shortlet are mutually exclusive per
  /// schema.md) -- lets the price card compute a real nightly-rate x
  /// nights = total breakdown instead of only ever echoing a flat string.
  final double? nightlyRate;
  final double? flatPrice;

  /// "sale" | "lease" -- only meaningful when [flatPrice] is set; labels
  /// the price row distinctly (a lease price reads differently from a
  /// one-time sale price even though both are flat amounts).
  final String? dealType;

  final DateTime? checkInDate;
  final DateTime? checkOutDate;
  final void Function(BookingHold hold) onProceedToCheckout;

  /// Confirmed real gap: on a booking failure (e.g. the dates were taken by
  /// someone else in the meantime), "Try again" previously just reset this
  /// screen's own controller state and re-rendered THIS SAME confirm screen
  /// with the SAME dates that just failed -- offering no actual way to
  /// change anything before resubmitting an attempt highly likely to fail
  /// again. When provided (booking_screen.dart wires this for date-bound
  /// listings), the error state's "Try again" uses this instead of
  /// `controller.restart()` alone, so the caller can also clear the chosen
  /// dates and send the user back to the Select Dates step. Falls back to
  /// `controller.restart()` when null (listings with no date-selection
  /// step at all -- there's nothing else to send the user back to).
  final VoidCallback? onTryAgain;

  @override
  State<BookingConfirmationScreen> createState() =>
      _BookingConfirmationScreenState();
}

class _BookingConfirmationScreenState extends State<BookingConfirmationScreen> {
  // Best-effort, independent of the controller/hold flow -- if this fails
  // (e.g. offline), the summary just shows 0% buyer fee, same fail-open
  // contract as ListingRepository.getCurrentBuyerFeePercentage's own
  // docstring. The backend's own hold-creation computation is always the
  // real, authoritative charge amount regardless of what this preview
  // shows.
  double _buyerFeePercentage = 0.0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    unawaited(_loadBuyerFeePercentage());
  }

  Future<void> _loadBuyerFeePercentage() async {
    final pct = await widget.listingRepository
        .getCurrentBuyerFeePercentage(widget.transactionType);
    if (!mounted) return;
    setState(() => _buyerFeePercentage = pct);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  bool get _hasDates => widget.checkInDate != null && widget.checkOutDate != null;

  int get _nights =>
      _hasDates ? widget.checkOutDate!.difference(widget.checkInDate!).inDays : 0;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm your booking')),
      body: SafeArea(child: _buildBody(controller)),
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
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Listing header -- an icon-badged title rather than bare
                // text, matching the "icon + heading" pattern used across
                // this app's other summary cards (e.g. checkout's own
                // Listing row).
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Icon(Icons.home_work_outlined,
                          color: colorScheme.onPrimaryContainer, size: 20),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        widget.listingTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (_hasDates) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const _SectionLabel('Dates'),
                  const SizedBox(height: AppSpacing.sm),
                  _DateRangeCard(
                      checkInDate: widget.checkInDate!,
                      checkOutDate: widget.checkOutDate!),
                ],
                const SizedBox(height: AppSpacing.lg),
                const _SectionLabel('Price details'),
                const SizedBox(height: AppSpacing.sm),
                _PriceSummaryCard(
                  nightlyRate: widget.nightlyRate,
                  flatPrice: widget.flatPrice,
                  dealType: widget.dealType,
                  nights: _nights,
                  buyerFeePercentage: _buyerFeePercentage,
                ),
              ],
            ),
          ),
        ),
        _BottomActionBar(
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
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
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
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = nearingExpiry
        ? colorScheme.error
        : Theme.of(context).extension<AppSemanticColors>()!.warning;
    final formatter = NumberFormat('#,##0', 'en_NG');
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // `badge-pop` on the countdown timer settling in when a
                // hold is created (Screen 6b Modernization Notes) -- keyed
                // once per hold so it pops on arrival, not on every tick.
                BadgePop(
                  triggerKey: hold.transactionId,
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock_clock, color: statusColor),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Hold active -- ${minutes}m ${seconds.toString().padLeft(2, '0')}s remaining',
                            style: TextStyle(
                                color: statusColor, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const _SectionLabel('Amount due'),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(color: colorScheme.outline),
                  ),
                  child: Text(
                    '₦${formatter.format(hold.grossAmount)}',
                    style: AppTypography.statDisplay
                        .copyWith(color: colorScheme.primary),
                  ),
                ),
              ],
            ),
          ),
        ),
        _BottomActionBar(
          child: ElevatedButton(
            onPressed: () => widget.onProceedToCheckout(hold),
            child: const Text('Proceed to checkout'),
          ),
        ),
      ],
    );
  }

  Widget _buildExpired() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _StatusIcon(icon: Icons.timer_off, color: colorScheme.error),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Your hold expired',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: colorScheme.error, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Someone else may now be able to book these dates.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: widget.controller.restart,
              child: const Text('Start again'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BookingController controller) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _StatusIcon(icon: Icons.error_outline, color: colorScheme.error),
          const SizedBox(height: AppSpacing.md),
          Text(
            controller.errorMessage ?? 'Something went wrong.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: widget.onTryAgain ?? controller.restart,
              child: const Text('Try again'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small caps-style section heading ("Dates", "Price details", "Amount
/// due") -- the same "label a group of related content" role
/// `_FilterSection` (filter_sheet.dart) already plays elsewhere, giving
/// this screen's cards a clear hierarchy instead of just stacking directly.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTypography.caption.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// Persistent bottom bar for this screen's primary action -- a top border
/// + surface background separates it from the scrollable content above,
/// same visual technique portfolio_list_screen.dart's `_BulkActionBar`
/// already uses for its own pinned action row.
class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outline)),
      ),
      child: SizedBox(width: double.infinity, height: 48, child: child),
    );
  }
}

/// Tinted circular icon badge for the Expired/Error status screens --
/// replaces a bare floating Icon with the same "icon in a soft-tinted
/// circle" treatment this app's celebratory/status views already use
/// elsewhere (e.g. become_host's Verified status view), so a "bad news"
/// moment still reads as considered rather than a plain warning glyph.
class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 36),
    );
  }
}

/// Replaces the old plain "2026-07-22 -> 2026-07-25" text line -- a raw
/// ISO-ish string with no visual structure, easy to misread and giving
/// check-in/check-out no distinct identity of their own. This card mirrors
/// the check-in/arrow/check-out layout travel and booking apps use
/// (Airbnb, booking.com), with each date given a real label, a
/// human-readable "Wed, 22 Jul" format, and the stay length spelled out
/// underneath so the two dates read as one coherent range, not two
/// unrelated numbers.
class _DateRangeCard extends StatelessWidget {
  const _DateRangeCard({required this.checkInDate, required this.checkOutDate});

  final DateTime checkInDate;
  final DateTime checkOutDate;

  int get _nights => checkOutDate.difference(checkInDate).inDays;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final nights = _nights;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _DateColumn(label: 'Check-in', date: checkInDate),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Icon(Icons.arrow_forward,
                    size: 18, color: colorScheme.onSurfaceVariant),
              ),
              Expanded(
                child: _DateColumn(label: 'Check-out', date: checkOutDate),
              ),
            ],
          ),
          if (nights > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Divider(height: 1, color: colorScheme.outline),
            const SizedBox(height: AppSpacing.sm),
            Text(
              nights == 1 ? '1 night' : '$nights nights',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _DateColumn extends StatelessWidget {
  const _DateColumn({required this.label, required this.date});

  final String label;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 14, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTypography.caption
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 2),
        // e.g. "Wed, 22 Jul" -- weekday gives an instant sense of "is this a
        // weekend booking" without needing a full calendar widget, and
        // omitting the year keeps it compact (a booking >12 months out is
        // an edge case, not the common path this card is optimized for).
        Text(
          DateFormat('EEE, d MMM').format(date),
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Itemized price breakdown -- the actual feature request this redesign
/// was for: previously the screen only ever showed a flat per-unit price
/// ("₦50,000 / night") with no total, even once check-in/check-out dates
/// (and therefore a real length of stay) were known. For Shortlet
/// listings this now shows "rate x nights" against the computed total;
/// for Commercial listings (a single flat price, nothing to multiply) it
/// shows one clearly-labeled price row instead.
///
/// FEAT-014's two-sided commission model adds a "Service fee" row on top
/// of the listing price -- the guest is actually charged
/// `listingPrice + buyerFeeAmount` (matching what the backend computes at
/// hold-creation time), so this preview must show that too rather than
/// quoting a lower number than what the hold will actually charge.
class _PriceSummaryCard extends StatelessWidget {
  const _PriceSummaryCard({
    required this.nightlyRate,
    required this.flatPrice,
    required this.dealType,
    required this.nights,
    required this.buyerFeePercentage,
  });

  final double? nightlyRate;
  final double? flatPrice;
  final String? dealType;
  final int nights;
  final double buyerFeePercentage;

  bool get _isNightly => nightlyRate != null;

  double get _listingPrice {
    if (_isNightly) return nightlyRate! * (nights > 0 ? nights : 1);
    return flatPrice ?? 0;
  }

  double get _buyerFeeAmount => _listingPrice * (buyerFeePercentage / 100);

  double get _grandTotal => _listingPrice + _buyerFeeAmount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final formatter = NumberFormat('#,##0', 'en_NG');
    String money(double v) => '₦${formatter.format(v)}';
    final showFee = buyerFeePercentage > 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isNightly)
            _PriceRow(
              label:
                  '${money(nightlyRate!)} x ${nights == 1 ? '1 night' : '${nights > 0 ? nights : 1} nights'}',
              value: money(_listingPrice),
            )
          else
            _PriceRow(
              label: dealType == 'lease' ? 'Lease price' : 'Price',
              value: money(_listingPrice),
            ),
          if (showFee) ...[
            const SizedBox(height: AppSpacing.sm),
            _PriceRow(
              label:
                  'Service fee (${buyerFeePercentage.toStringAsFixed(buyerFeePercentage.truncateToDouble() == buyerFeePercentage ? 0 : 1)}%)',
              value: money(_buyerFeeAmount),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: colorScheme.outline),
          const SizedBox(height: AppSpacing.sm),
          _PriceRow(label: 'Total', value: money(_grandTotal), emphasize: true),
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: emphasize
                ? Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)
                : AppTypography.body
                    .copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
        Text(
          value,
          style: emphasize
              ? AppTypography.statSmall.copyWith(color: colorScheme.primary)
              : AppTypography.body,
        ),
      ],
    );
  }
}
