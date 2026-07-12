/// screens.md Screen 4: Home Feed (FEAT-006). The app's post-login landing
/// screen -- one of the 4 bottom-nav tab roots (see
/// core/routing/app_shell.dart, which owns the actual `NavigationBar` and
/// each tab's role-based visibility; this screen owns only its own
/// `AppBar` + content, per screens.md's layout). Search is NOT a tab --
/// per product-shaper's IA review, this screen's own prominent search
/// entry field below the `AppBar` is the primary entry point into Search
/// Results instead (screens.md Screen 4 Layout note).
///
/// Reuses the Search feature's `GET /v1/search/listings` for "nearby"
/// listings rather than a separate `/listings/nearby` endpoint -- that
/// endpoint doesn't exist, and search's geospatial capability already
/// covers exactly this need (deliberate reuse decision, not a placeholder).
/// `GET /notifications/count` (screens.md's notification bell data source)
/// does not exist either -- FEAT-022 (Push Notifications) is push
/// delivery + preferences only, an in-app notification center/count is a
/// separate, not-yet-scoped feature, so the bell renders without a badge
/// count for now rather than calling an endpoint that doesn't exist.
/// The location indicator (Components table: "Shows/change current search
/// location") is similarly a static label today -- changing it needs the
/// same device-location plugin this file's own `_fallbackLatitude`/
/// `_fallbackLongitude` TODO already defers.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/route_names.dart';
import '../../../core/theme/app_spacing.dart';
import '../../push_notifications/data/push_notification_service.dart';
import '../../search/data/search_models.dart';
import '../../search/data/search_repository.dart';
import '../../search/screens/listing_result_card.dart';

enum _ScreenState { loading, loaded, empty, error, offline }

/// screens.md Edge Cases: "default to a configured city-level fallback
/// rather than blocking the feed entirely" when there's no device location
/// permission and no typed location. Lagos Island, matching the city/state
/// default used elsewhere in this codebase (e.g. listing creation).
/// TODO: replace with an actual device-location plugin (geolocator) --
/// same deferred wiring noted in create_listing_screen.dart's location
/// step; Home Feed's own AC is satisfied by the fallback alone in the
/// meantime, not blocked on it.
const _fallbackLatitude = 6.5244;
const _fallbackLongitude = 3.3792;

class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({
    super.key,
    required this.searchRepository,
    required this.pushNotificationService,
  });

  final SearchRepository searchRepository;
  final PushNotificationService pushNotificationService;

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen> {
  _ScreenState _state = _ScreenState.loading;
  List<ListingSearchResult> _nearYou = [];
  List<ListingSearchResult> _recentlyAdded = [];

  @override
  void initState() {
    super.initState();
    _load();
    // Fire-and-forget: Home Feed is the one tab every successful auth flow
    // reaches first (see auth_screen.dart's _onAuthSuccess), so this is
    // where FCM registration happens for the session. Never awaited -- a
    // push-registration failure must not delay/block the listings fetch
    // above, and initialize() itself never throws (see its own docstring).
    widget.pushNotificationService.initialize();
  }

  Future<void> _load() async {
    setState(() => _state = _ScreenState.loading);
    try {
      final nearYouFuture = widget.searchRepository.search(
        const SearchQueryState(
          latitude: _fallbackLatitude,
          longitude: _fallbackLongitude,
          radiusKm: 15,
          sortBy: SortField.distance,
        ),
        pageSize: 10,
      );
      final recentFuture = widget.searchRepository.search(
        const SearchQueryState(
          latitude: _fallbackLatitude,
          longitude: _fallbackLongitude,
          radiusKm: 50,
          sortBy: SortField.newest,
        ),
        pageSize: 10,
      );

      final nearYou = await nearYouFuture;
      final recent = await recentFuture;

      if (!mounted) return;
      setState(() {
        _nearYou = nearYou.results;
        _recentlyAdded = recent.results;
        _state = (_nearYou.isEmpty && _recentlyAdded.isEmpty)
            ? _ScreenState.empty
            : _ScreenState.loaded;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final isOffline = e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout;
      setState(() => _state = isOffline ? _ScreenState.offline : _ScreenState.error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _ScreenState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('De-Duke'),
        automaticallyImplyLeading: false, // tab root -- never a back arrow
        actions: [
          // Components table: "Location indicator -- Shows/change current
          // search location". Static label for now -- see file header for
          // why "change" isn't wired yet.
          TextButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Changing location is not available yet.')),
            ),
            icon: const Icon(Icons.location_on_outlined, size: 18),
            label: const Text('Lagos'),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Notifications',
            onPressed: () {}, // no in-app notification center yet -- see file header
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Components table: "Search entry field -- Tappable
            // TextField-styled row -- Navigate to Search Results". The
            // primary Search entry point now that it's not a bottom-nav
            // tab (see file header) -- always visible, regardless of this
            // screen's own load state below, so Search stays reachable
            // even while Home Feed itself is loading/erroring/offline.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
              child: _SearchEntryField(onTap: () => context.pushNamed(RouteNames.search)),
            ),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_state) {
      case _ScreenState.loading:
        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: 5,
          itemBuilder: (_, __) => Container(
            height: 96,
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
        );
      case _ScreenState.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: AppSpacing.sm),
              const Text('Something went wrong'),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        );
      case _ScreenState.offline:
        return Column(
          children: [
            MaterialBanner(
              content: const Text("You're offline. Showing last saved listings."),
              actions: [
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
            if (_nearYou.isNotEmpty || _recentlyAdded.isNotEmpty)
              Expanded(child: _buildSections(context)),
          ],
        );
      case _ScreenState.empty:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off_outlined, size: 48),
              const SizedBox(height: AppSpacing.sm),
              const Text('No listings near you yet'),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: () => context.pushNamed(RouteNames.search),
                child: const Text('Widen search'),
              ),
            ],
          ),
        );
      case _ScreenState.loaded:
        return RefreshIndicator(onRefresh: _load, child: _buildSections(context));
    }
  }

  Widget _buildSections(BuildContext context) {
    return ListView(
      children: [
        // No separate "Search listings" button here -- the persistent
        // search entry field above `_buildBody` (visible across every
        // state, not just Loaded) is this screen's one Search entry
        // point now; a second button here would be a redundant, easy-to-
        // drift-out-of-sync duplicate of it.
        const SizedBox(height: AppSpacing.sm),
        if (_nearYou.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text('Near You', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final result in _nearYou)
            ListingResultCard(
              result: result,
              onTap: () => context.pushNamed(
                RouteNames.listingDetail,
                pathParameters: {'id': result.id},
              ),
            ),
        ],
        if (_recentlyAdded.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text('Recently Added', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final result in _recentlyAdded)
            ListingResultCard(
              result: result,
              onTap: () => context.pushNamed(
                RouteNames.listingDetail,
                pathParameters: {'id': result.id},
              ),
            ),
        ],
      ],
    );
  }
}

/// screens.md Screen 4 Layout: "Prominent search entry point styled as a
/// large tappable search field, navigating to Search Results on tap".
/// Deliberately not a real `TextField` -- it's tap-only navigation (the
/// actual query text entry happens on Search Results itself, per Screen 5),
/// so an `InkWell` styled to look like one avoids a focusable-but-inert
/// text field that would confuse screen readers/keyboard focus order.
class _SearchEntryField extends StatelessWidget {
  const _SearchEntryField({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.md),
          child: Row(
            children: [
              Icon(Icons.search, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Search by location or keyword',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
