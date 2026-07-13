/// FEAT-012 AC: "Agency admin can invite team members to a shared agency
/// account." Not one of screens.md's numbered screens (Screens 13-16 don't
/// include a dedicated team-roster screen) -- reached from Agency
/// Dashboard's AppBar action, mirroring the shape of the Admin Web
/// Console's own Staff Account Management screen (Screen 25) at the
/// mobile-agency scale.
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

class TeamManagementScreen extends StatefulWidget {
  const TeamManagementScreen({super.key, required this.repository});

  final AgencyRepository repository;

  @override
  State<TeamManagementScreen> createState() => _TeamManagementScreenState();
}

class _TeamManagementScreenState extends State<TeamManagementScreen> {
  _ScreenState _state = _ScreenState.loading;
  List<TeamMember> _team = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _ScreenState.loading);
    try {
      final team = await widget.repository.getTeam();
      if (!mounted) return;
      setState(() {
        _team = team;
        _state = team.isEmpty ? _ScreenState.empty : _ScreenState.loaded;
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

  Future<void> _openInviteDialog() async {
    final result = await showDialog<_InviteFormResult>(
      context: context,
      builder: (context) => const _InviteMemberDialog(),
    );
    if (result == null) return;
    try {
      await widget.repository.inviteTeamMember(
        fullName: result.fullName,
        email: result.email,
        agencyRole: result.agencyRole,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.fullName} has been invited.')),
      );
      await _load();
    } on AgencyException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Team')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openInviteDialog,
        icon: const Icon(Icons.person_add_alt_outlined),
        label: const Text('Invite'),
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_state) {
      case _ScreenState.loading:
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          itemCount: 3,
          itemBuilder: (_, __) => const SkeletonRow(),
        );
      case _ScreenState.empty:
        return EmptyStateView(
          title: "You're working solo",
          message: 'Invite a team member to start assigning leads.',
          actionLabel: 'Invite Team Member',
          onAction: _openInviteDialog,
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
              content: const Text("You're offline."),
              actions: [
                TextButton(onPressed: _load, child: const Text('Retry'))
              ],
            ),
            if (_team.isNotEmpty) Expanded(child: _buildList(context)),
          ],
        );
      case _ScreenState.loaded:
        return RefreshIndicator(onRefresh: _load, child: _buildList(context));
    }
  }

  Widget _buildList(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: _team.length,
      itemBuilder: (context, index) {
        final member = _team[index];
        return ListStaggerItem(
          index: index,
          child: Container(
            margin: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.sm,
            ),
            child: Row(
              children: [
                CircleAvatar(
                  child: Text(member.fullName.isNotEmpty
                      ? member.fullName[0].toUpperCase()
                      : '?'),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member.fullName, style: AppTypography.h3),
                      Text(
                        member.email ?? '',
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(AppRadii.full),
                  ),
                  child: Text(
                    member.agencyRole,
                    style: AppTypography.caption
                        .copyWith(color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InviteFormResult {
  const _InviteFormResult(this.fullName, this.email, this.agencyRole);
  final String fullName;
  final String email;
  final String agencyRole;
}

class _InviteMemberDialog extends StatefulWidget {
  const _InviteMemberDialog();

  @override
  State<_InviteMemberDialog> createState() => _InviteMemberDialogState();
}

class _InviteMemberDialogState extends State<_InviteMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  String _role = 'agent';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invite Team Member'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              validator: (value) => (value == null || !value.contains('@'))
                  ? 'Enter a valid email'
                  : null,
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: const [
                DropdownMenuItem(value: 'agent', child: Text('Agent')),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
              ],
              onChanged: (value) => setState(() => _role = value ?? 'agent'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(
              _InviteFormResult(_nameController.text.trim(),
                  _emailController.text.trim(), _role),
            );
          },
          child: const Text('Send Invite'),
        ),
      ],
    );
  }
}
