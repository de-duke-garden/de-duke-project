/// screens.md Screen 2: Role Selection (FEAT-003). First-run only (per
/// that screen's Edge Cases -- role can be changed later from Account
/// Settings via the same repository call, see account_settings_screen.dart).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';
import '../../../core/theme/app_spacing.dart';
import '../../auth/data/auth_repository.dart';

enum _ScreenState { defaultState, selecting, error, offline }

class _RoleOption {
  const _RoleOption(this.value, this.label, this.description, this.icon);
  final String value;
  final String label;
  final String description;
  final IconData icon;
}

// SELF_SERVICE_ROLES order/values must match app/schemas/auth.py exactly.
const _roleOptions = [
  _RoleOption(
    'seeker',
    'Individual Seeker',
    'Find and book properties for yourself',
    Icons.person_outline,
  ),
  _RoleOption(
    'individual_host',
    'Individual Host',
    'List your own property',
    Icons.home_outlined,
  ),
  _RoleOption(
    'agency',
    'Agency',
    'Manage listings for multiple clients',
    Icons.business_outlined,
  ),
  _RoleOption(
    'corporate',
    'Business / Corporate',
    'Book properties on behalf of a company',
    Icons.apartment_outlined,
  ),
];

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key, required this.repository});

  final AuthRepository repository;

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  _ScreenState _state = _ScreenState.defaultState;
  String? _selectedRole;

  /// screens.md Data Flow step 3: routes to Become a Host (Host/Agency) or
  /// Home Feed (Seeker/Corporate) per user_flow.md Flow 2.
  void _routeAfterSelection(String role) {
    if (!mounted) return;
    if (role == 'individual_host' || role == 'agency') {
      context.goNamed(RouteNames.verification);
    } else {
      context.goNamed(RouteNames.home);
    }
  }

  Future<void> _selectRole(String role) async {
    setState(() {
      _selectedRole = role;
      _state = _ScreenState.selecting;
    });
    try {
      await widget.repository.updateRole(role);
      _routeAfterSelection(role);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = e.message == 'offline' ? _ScreenState.offline : _ScreenState.error;
      });
    }
  }

  void _skip() => _selectRole('seeker');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('How will you use De-Duke?'),
        automaticallyImplyLeading: false, // first-run flow, no back button
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_state == _ScreenState.error)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: MaterialBanner(
                  content: const Text("Couldn't save your selection, try again."),
                  actions: [
                    TextButton(
                      onPressed: () => setState(() => _state = _ScreenState.defaultState),
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ),
            if (_state == _ScreenState.offline)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: MaterialBanner(
                  content: const Text(
                    "You're offline. Selection not saved until reconnected.",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => setState(() => _state = _ScreenState.defaultState),
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  for (final option in _roleOptions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _RoleCard(
                        option: option,
                        isSelected: _selectedRole == option.value,
                        isSaving:
                            _state == _ScreenState.selecting && _selectedRole == option.value,
                        onTap: _state == _ScreenState.selecting
                            ? null
                            : () => _selectRole(option.value),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: TextButton(
                onPressed: _state == _ScreenState.selecting ? null : _skip,
                child: const Text('Skip for now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.option,
    required this.isSelected,
    required this.isSaving,
    required this.onTap,
  });

  final _RoleOption option;
  final bool isSelected;
  final bool isSaving;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(option.icon, size: 32),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.label, style: Theme.of(context).textTheme.titleMedium),
                    Text(option.description, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (isSaving)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
