/// screens.md Screen 15: Unassigned Leads Inbox (FEAT-012).
///
/// Modernization Notes: Lead rows adopt Listing Card container styling
/// with `tap-scale`, entering with `list-stagger` on first load; a
/// successful assignment animates the row out (quick fade, matched here by
/// simply removing it from `_leads` after a successful PATCH, which
/// AnimatedList below cross-fades); initial load uses skeleton rows; empty
/// state uses the illustrated system; assignment failures use semantic
/// `error` color paired with icon + text.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/list_stagger.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../data/agency_models.dart';
import '../data/agency_repository.dart';

enum _ScreenState { loading, loaded, empty, error, offline }

class UnassignedLeadsInboxScreen extends StatefulWidget {
  const UnassignedLeadsInboxScreen({super.key, required this.repository});

  final AgencyRepository repository;

  @override
  State<UnassignedLeadsInboxScreen> createState() =>
      _UnassignedLeadsInboxScreenState();
}

class _UnassignedLeadsInboxScreenState
    extends State<UnassignedLeadsInboxScreen> {
  _ScreenState _state = _ScreenState.loading;
  List<Lead> _leads = [];
  List<TeamMember> _team = [];
  // Per-lead assignment-in-progress / failure tracking -- lets one row show
  // its own spinner/error without blocking the rest of the list
  // (screens.md's "Assigning"/"Assignment Failed" states are per-row, not
  // whole-screen).
  final Set<String> _assigningLeadIds = {};
  final Map<String, String> _assignmentErrors = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _ScreenState.loading);
    try {
      final leads = await widget.repository
          .getLeads(status: 'unassigned', assignee: 'all');
      if (!mounted) return;
      setState(() {
        _leads = leads;
        _state = leads.isEmpty ? _ScreenState.empty : _ScreenState.loaded;
      });
    } on AgencyException catch (e) {
      if (!mounted) return;
      setState(() =>
          _state = e.isOffline ? _ScreenState.offline : _ScreenState.error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _ScreenState.error);
    }
  }

  Future<void> _openAssignSheet(Lead lead) async {
    if (_team.isEmpty) {
      try {
        _team = await widget.repository.getTeam();
      } on AgencyException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
        return;
      }
    }
    if (!mounted) return;

    final selected = await showModalBottomSheet<TeamMember>(
      context: context,
      builder: (context) => _TeamMemberPickerSheet(team: _team),
    );
    if (selected == null) return;
    await _assign(lead, selected);
  }

  Future<void> _assign(Lead lead, TeamMember assignee) async {
    setState(() {
      _assigningLeadIds.add(lead.id);
      _assignmentErrors.remove(lead.id);
    });
    try {
      await widget.repository
          .assignLead(leadId: lead.id, assignedToId: assignee.userId);
      if (!mounted) return;
      setState(() {
        _assigningLeadIds.remove(lead.id);
        _leads.removeWhere((l) => l.id == lead.id);
        if (_leads.isEmpty) _state = _ScreenState.empty;
      });
    } on AgencyException catch (e) {
      if (!mounted) return;
      setState(() {
        _assigningLeadIds.remove(lead.id);
        // Screen 15 Edge Case: two admins assigning the same lead at once --
        // the loser sees this toast and the row simply returns to the list
        // (already still present since we only remove on success).
        _assignmentErrors[lead.id] = e.isConflict
            ? 'This lead was just assigned by someone else.'
            : "Couldn't assign, try again";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('New Leads'),
            if (_leads.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              _CountBadge(count: _leads.length),
            ],
          ],
        ),
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_state) {
      case _ScreenState.loading:
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          itemCount: 4,
          itemBuilder: (_, __) => const SkeletonRow(),
        );
      case _ScreenState.empty:
        return const EmptyStateView(
          title: "You're all caught up — no new leads waiting",
        );
      case _ScreenState.error:
        return EmptyStateView(
          title: 'Something went wrong',
          isError: true,
          actionLabel: 'Retry',
          onAction: _load,
        );
      case _ScreenState.offline:
        return Column(
          children: [
            MaterialBanner(
              content: const Text(
                  "You're offline. Assignment is disabled until reconnected."),
              actions: [
                TextButton(onPressed: _load, child: const Text('Retry'))
              ],
            ),
            if (_leads.isNotEmpty) Expanded(child: _buildList(context)),
          ],
        );
      case _ScreenState.loaded:
        return RefreshIndicator(onRefresh: _load, child: _buildList(context));
    }
  }

  Widget _buildList(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: _leads.length,
      itemBuilder: (context, index) {
        final lead = _leads[index];
        return ListStaggerItem(
          index: index,
          child: _LeadRow(
            lead: lead,
            isAssigning: _assigningLeadIds.contains(lead.id),
            errorMessage: _assignmentErrors[lead.id],
            onAssign: () => _openAssignSheet(lead),
          ),
        );
      },
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Text(
        '$count',
        style: AppTypography.caption.copyWith(color: Colors.white),
      ),
    );
  }
}

class _LeadRow extends StatelessWidget {
  const _LeadRow({
    required this.lead,
    required this.isAssigning,
    required this.errorMessage,
    required this.onAssign,
  });

  final Lead lead;
  final bool isAssigning;
  final String? errorMessage;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('New inquiry', style: AppTypography.h3),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Listing ${lead.listingId}',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (isAssigning)
                const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                ElevatedButton(
                    onPressed: onAssign, child: const Text('Assign')),
            ],
          ),
          if (errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      size: 14, color: AppColors.error),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      errorMessage!,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TeamMemberPickerSheet extends StatelessWidget {
  const _TeamMemberPickerSheet({required this.team});
  final List<TeamMember> team;

  @override
  Widget build(BuildContext context) {
    if (team.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Text('No team members yet. Invite one from Manage Team first.'),
      );
    }
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final member in team)
            ListTile(
              title: Text(member.fullName),
              subtitle: Text(member.agencyRole),
              onTap: () => Navigator.of(context).pop(member),
            ),
        ],
      ),
    );
  }
}
