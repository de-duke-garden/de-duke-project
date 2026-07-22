/// Report-a-listing / report-a-conversation bottom sheet -- FEAT-009
/// (In-App Reporting). screens.md Screen 6's Report IconButton opens this
/// for a listing; the Chat Thread screen's overflow-menu "Report
/// conversation" action opens the same sheet for a conversation.
///
/// Accessibility (AGENTS.md): reason choices use a RadioListTile group
/// (icon+text per option, never color alone) with each row at least
/// AppSizing.minTouchTarget (48x48) tall; submit/cancel buttons use the
/// standard AppSizing.buttonHeight (48) height.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/report_repository.dart';

enum _SubmitState { idle, submitting, success, error }

/// What's being reported -- determines which repository call fires.
enum ReportTargetKind { listing, conversation }

/// Opens the report sheet as a modal bottom sheet. Returns true if a report
/// was successfully submitted (screens.md Screen 6's "Report Submitted"
/// confirmation toast is shown by the caller on a true result), false/null
/// otherwise.
Future<bool?> showReportSheet(
  BuildContext context, {
  required ReportRepository repository,
  required ReportTargetKind kind,
  required String targetId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _ReportSheet(
      repository: repository,
      kind: kind,
      targetId: targetId,
    ),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.repository,
    required this.kind,
    required this.targetId,
  });

  final ReportRepository repository;
  final ReportTargetKind kind;
  final String targetId;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportReason _reason = ReportReason.fake;
  final _detailController = TextEditingController();
  _SubmitState _state = _SubmitState.idle;
  String? _errorMessage;

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _state = _SubmitState.submitting;
      _errorMessage = null;
    });
    try {
      if (widget.kind == ReportTargetKind.listing) {
        await widget.repository.reportListing(
          widget.targetId,
          reason: _reason,
          detail: _detailController.text,
        );
      } else {
        await widget.repository.reportConversation(
          widget.targetId,
          reason: _reason,
          detail: _detailController.text,
        );
      }
      if (!mounted) return;
      setState(() => _state = _SubmitState.success);
      // Brief confirmation state so the icon+text success feedback is
      // visible before the sheet closes and hands the toast to the caller.
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _SubmitState.error;
        _errorMessage = "Couldn't submit your report. Try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.kind == ReportTargetKind.listing
        ? 'Report listing'
        : 'Report conversation';
    final submitting = _state == _SubmitState.submitting;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        bottom: AppSpacing.md + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flag_outlined, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: AppSpacing.sm),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Why are you reporting this?',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            for (final reason in ReportReason.values)
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: RadioListTile<ReportReason>(
                  value: reason,
                  groupValue: _reason,
                  onChanged: submitting
                      ? null
                      : (value) => setState(() => _reason = value!),
                  title: Text(reason.label),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _detailController,
              enabled: !submitting,
              minLines: 2,
              maxLines: 4,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Additional details (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_state == _SubmitState.error) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(Icons.error_outline,
                      color: Theme.of(context).colorScheme.error, size: 20),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      _errorMessage ?? 'Something went wrong.',
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ],
              ),
            ],
            if (_state == _SubmitState.success) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      color: Theme.of(context)
                          .extension<AppSemanticColors>()!
                          .success,
                      size: 20),
                  const SizedBox(width: AppSpacing.xs),
                  Text("Thanks, we'll review this.",
                      style: TextStyle(
                          color: Theme.of(context)
                              .extension<AppSemanticColors>()!
                              .success)),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: submitting ? null : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: submitting || _state == _SubmitState.success
                          ? null
                          : _submit,
                      child: submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Submit report'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
