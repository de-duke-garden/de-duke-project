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
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_repository.dart';
import '../theme/app_colors.dart';

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
  /// Live-updating role source -- `AuthRepository.currentRoleNotifier`
  /// (see that field's docstring). Previously this shell fetched the role
  /// exactly ONCE in `initState` and stored it in local `_role` state, so
  /// changing role via Account Settings' "Change role" re-entry point
  /// (FEAT-003) never updated the bottom nav's Dashboard/Agency tab until
  /// the app was force-closed and relaunched -- confirmed real bug, fixed
  /// here by listening to the shared notifier instead of a one-shot fetch.
  /// `ValueListenableBuilder` below rebuilds the nav bar the instant
  /// `AuthRepository.getCurrentUser()`/`updateRole()` updates it, from
  /// anywhere in the app, without this widget needing to be recreated.
  String? get _role => widget.authRepository.currentRoleNotifier.value;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  /// Seeds `currentRoleNotifier` on first shell mount (e.g. a fresh app
  /// launch, before anything else has called `getCurrentUser()` yet).
  /// Every subsequent role change updates the notifier directly wherever
  /// it happens (Account Settings' role change, Role Selection) --
  /// `ValueListenableBuilder` picks those up on its own without calling
  /// this again.
  Future<void> _loadRole() async {
    try {
      await widget.authRepository.getCurrentUser();
    } catch (_) {
      // Never blocks the shell from rendering -- worst case, the Dashboard
      // tab stays hidden until a later successful fetch elsewhere in the
      // app (e.g. Account Settings loading the profile) updates the shared
      // notifier; acceptable given a role fetch failure here almost always
      // means the session itself is bad, which surfaces elsewhere too.
    }
  }

  /// screens.md: "Dashboard (Host/Agency, shown per role)" -- kept as a
  /// persistent bottom-nav tab per product-shaper's IA review (Host/Agency
  /// personas open it many times per session; nesting it under Account
  /// Settings would add friction to a high-frequency action for exactly
  /// the users who rely on it most, per screens.md Screen 4's Edge Cases
  /// note).
  bool get _showsHostDashboardTab => _role == 'host';

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
    // Rebuilds this shell (and only this shell -- widget.navigationShell's
    // own branch subtrees are untouched) whenever currentRoleNotifier
    // changes, e.g. right after Account Settings' "Change role" completes
    // its PATCH /v1/auth/me/role call -- no app restart needed. `_role`
    // reads the same notifier, so it always reflects whatever this builder
    // was just called with.
    return ValueListenableBuilder<String?>(
      valueListenable: widget.authRepository.currentRoleNotifier,
      builder: (context, _, __) => _buildShell(context),
    );
  }

  Widget _buildShell(BuildContext context) {
    final currentBranchIndex = widget.navigationShell.currentIndex;
    // Falls back to 0 (Home) rather than a negative/invalid selectedIndex
    // -- can only happen if a deep link lands directly on the Dashboard
    // branch (/host) for a non-host account, a real but rare edge case
    // (the Dashboard screens themselves still gate on verification/role
    // server-side regardless of how the tab bar renders). Also now the
    // landing path right after a role change removes the branch the user
    // was previously on (e.g. Agency -> Guest removes branch index 3).
    final onHiddenBranch = !_visibleBranches.contains(currentBranchIndex);
    final selectedVisibleIndex = onHiddenBranch
        ? 0
        : _visibleBranches.indexOf(currentBranchIndex);

    // If a role change just removed the branch currently being VIEWED
    // (not merely a deep-link edge case, but a live "I was looking at the
    // Agency dashboard and my role just became Guest" moment), the nav
    // bar above already re-highlights Home -- but `widget.navigationShell`
    // itself is still showing the now-hidden branch's body underneath it
    // until something actually navigates away from it. Scheduled for
    // after this frame (navigating mid-build is unsafe); a no-op on every
    // other rebuild since `onHiddenBranch` is false whenever the current
    // branch is still valid for the (possibly just-changed) role.
    if (onHiddenBranch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_visibleBranches.contains(widget.navigationShell.currentIndex)) {
          widget.navigationShell.goBranch(0);
        }
      });
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Explicit, rather than the Material 3 default (a tonal "elevated
    // surface" color derived from the ColorScheme, subtly different from
    // flat AppColors.surface) -- fixed to a known value so the Android
    // system navigation bar below can be set to this EXACT color rather
    // than guessing at M3's elevation math, closing the visible seam
    // between the two on these 4 tab-root screens specifically. Screens
    // pushed outside this shell (Listing Detail, Chat Thread, Checkout,
    // etc. -- no bottom nav bar of their own) keep the app-wide default
    // AnnotatedRegion set in main.dart instead.
    final navBarColor = isDark ? AppColors.surfaceDark : AppColors.surface;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: navBarColor,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: Scaffold(
        body: widget.navigationShell,
        bottomNavigationBar: NavigationBar(
          backgroundColor: navBarColor,
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
      ),
    );
  }
}
