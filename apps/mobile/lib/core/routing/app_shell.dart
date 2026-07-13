/// Bottom-nav shell -- wraps the `StatefulShellRoute` in app_router.dart's
/// 4 branch navigators (Home, Chat, Dashboard, Profile) per screens.md
/// Screen 4's "BottomNavigationBar with tabs: Home, Chat, Dashboard
/// (Host/Agency, shown per role), Profile". Search is deliberately NOT a
/// branch here -- product-shaper's IA review concluded it's better reached
/// via Home Feed's own prominent search entry field (a stronger, more
/// discoverable affordance than a nav-bar icon) than as a persistent tab;
/// see screens.md Screen 4's Layout note.
///
/// Fixes a real bug in the original flat-route setup: the bottom nav bar
/// lived on Home Feed's own `Scaffold`, so it only ever appeared on
/// `/home` itself and disappeared the instant any other route (Chat,
/// Dashboard, Profile, or anything pushed on top of them) became active.
/// `StatefulShellRoute.indexedStack` keeps this shell (and each branch's
/// own navigation stack) alive and persistent across tab switches --
/// switching tabs preserves scroll position/form state in the tab being
/// left, exactly like a native bottom-tab app.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_repository.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.navigationShell,
    required this.authRepository,
  });

  final StatefulNavigationShell navigationShell;
  final AuthRepository authRepository;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  String? _role;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  /// Resolves the caller's role once per shell lifetime (not per-tab) --
  /// screens.md Screen 4 Data Requirements: "User's role (to show correct
  /// dashboard tab) -- from auth context." Centralized here (rather than
  /// duplicated per-screen) means one fetch, not one per screen, and the
  /// nav bar itself (not just individual screens) reacts to it.
  Future<void> _loadRole() async {
    try {
      final user = await widget.authRepository.getCurrentUser();
      if (!mounted) return;
      setState(() => _role = user.role);
    } catch (_) {
      // Never blocks the shell from rendering -- worst case, the Dashboard
      // tab stays hidden until a later successful fetch (e.g. this widget
      // is never rebuilt to retry today, but a full app relaunch will
      // retry; acceptable given a role fetch failure here almost always
      // means the session itself is bad, which surfaces elsewhere too).
    }
  }

  /// screens.md: "Dashboard (Host/Agency, shown per role)" -- kept as a
  /// persistent bottom-nav tab per product-shaper's IA review (Host/Agency
  /// personas open it many times per session; nesting it under Account
  /// Settings would add friction to a high-frequency action for exactly
  /// the users who rely on it most, per screens.md Screen 4's Edge Cases
  /// note).
  bool get _showsHostDashboardTab => _role == 'individual_host';

  /// Screen 13 (Agency Dashboard, FEAT-012/FEAT-019) -- an `agency` account
  /// (root or invited team member; both share `User.role == 'agency'` per
  /// agency_service.py's own documented reasoning) gets the Agency
  /// Dashboard tab instead of the Host Dashboard tab.
  bool get _showsAgencyDashboardTab => _role == 'agency';

  /// Branch index -> visible NavigationBar index mapping. Branch order is
  /// fixed by app_router.dart's StatefulShellRoute.indexedStack declaration
  /// (0=Home, 1=Chat, 2=Host Dashboard, 3=Agency Dashboard, 4=Profile) --
  /// at most one of Host/Agency Dashboard is ever visible for a given role,
  /// so the branch-index vs. visible-destination-index spaces diverge and
  /// must be mapped explicitly both ways.
  List<int> get _visibleBranches {
    if (_showsHostDashboardTab) return const [0, 1, 2, 4];
    if (_showsAgencyDashboardTab) return const [0, 1, 3, 4];
    return const [0, 1, 4];
  }

  @override
  Widget build(BuildContext context) {
    final currentBranchIndex = widget.navigationShell.currentIndex;
    // Falls back to 0 (Home) rather than a negative/invalid selectedIndex
    // -- can only happen if a deep link lands directly on the Dashboard
    // branch (/host) for a non-host account, a real but rare edge case
    // (the Dashboard screens themselves still gate on verification/role
    // server-side regardless of how the tab bar renders).
    final selectedVisibleIndex = _visibleBranches.contains(currentBranchIndex)
        ? _visibleBranches.indexOf(currentBranchIndex)
        : 0;

    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedVisibleIndex,
        onDestinationSelected: (visibleIndex) {
          final branchIndex = _visibleBranches[visibleIndex];
          widget.navigationShell.goBranch(
            branchIndex,
            // Tapping the already-active tab resets that tab's own stack
            // back to its root -- standard bottom-nav behavior (e.g.
            // tapping Home again while deep in Home's own pushed screens
            // returns to Home Feed itself).
            initialLocation: branchIndex == currentBranchIndex,
          );
        },
        destinations: [
          const NavigationDestination(
              icon: Icon(Icons.home_outlined), label: 'Home'),
          const NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
          if (_showsHostDashboardTab)
            const NavigationDestination(
                icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          if (_showsAgencyDashboardTab)
            const NavigationDestination(
                icon: Icon(Icons.apartment_outlined), label: 'Agency'),
          const NavigationDestination(
              icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}
