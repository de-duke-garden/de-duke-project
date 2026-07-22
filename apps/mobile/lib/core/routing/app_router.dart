/// go_router configuration -- route paths match docs/De-Duke/screens.md's
/// Screen Inventory table exactly (route path column), and the nesting
/// below mirrors that table's parent/child relationships (e.g.
/// `/listing/:id/confirm-booking` is a child of `/listing/:id`,
/// `/verification/:hostType` is a child of `/verification`) rather than a
/// flat list of unrelated absolute paths.
///
/// The 5 bottom-nav tab roots (Home, Search, Chat, Dashboard, Profile --
/// screens.md Screen 4's layout) live inside a `StatefulShellRoute.indexedStack`
/// (see app_shell.dart) so the nav bar and each tab's own navigation stack
/// persist across tab switches. Every other screen is a plain top-level
/// `GoRoute`, which pushes full-screen ABOVE the shell (no bottom nav
/// visible) -- this matches how Listing Detail, Chat Thread, Checkout,
/// etc. are actually specified (their own dedicated `AppBar`, no bottom
/// nav coexisting), and is the standard go_router pattern for a shell.
///
/// Feature subagents register their real screens here; this file stays a
/// shared module (read/extend, do not restructure without coordinating
/// across subagents to avoid navigation merge conflicts).
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/agency/data/agency_repository.dart';
import '../../features/agency/screens/agency_dashboard_screen.dart';
import '../../features/agency/screens/lead_analytics_screen.dart';
import '../../features/agency/screens/portfolio_list_screen.dart';
import '../../features/agency/screens/team_management_screen.dart';
import '../../features/agency/screens/unassigned_leads_inbox_screen.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/screens/accept_invite_screen.dart';
import '../../features/auth/screens/auth_screen.dart';
import '../../features/become_host/data/host_account_models.dart';
import '../../features/become_host/data/host_account_repository.dart';
import '../../features/become_host/screens/document_submission_screen.dart';
import '../../features/chat/data/chat_api.dart';
import '../../features/chat/data/chat_repository.dart';
import '../../features/chat/screens/chat_inbox_screen.dart';
import '../../features/chat/screens/chat_thread_screen.dart';
import '../../features/support/data/support_api.dart';
import '../../features/support/data/support_repository.dart';
import '../../features/support/screens/support_screen.dart';
import '../../features/account_settings/data/account_deletion_repository.dart';
import '../../features/account_settings/screens/account_settings_screen.dart';
import '../../features/become_host/screens/host_type_selection_screen.dart';
import '../../features/booking/data/booking_api.dart';
import '../../features/booking/logic/booking_controller.dart';
import '../../features/booking/screens/booking_screen.dart';
import '../../features/checkout/data/checkout_repository.dart';
import '../../features/checkout/screens/checkout_screen.dart';
import '../../features/checkout/screens/payment_confirmation_screen.dart';
import '../../features/listings/data/listing_repository.dart';
import '../../features/listings/screens/create_listing_screen.dart';
import '../../features/listings/screens/edit_listing_screen.dart';
import '../../features/listings/screens/listing_detail_screen.dart';
import '../../features/reporting/data/report_repository.dart';
import '../../features/search/data/search_repository.dart';
import '../../features/share_summary/data/share_repository.dart';
import '../../features/search/screens/saved_searches_screen.dart';
import '../../features/search/screens/search_results_screen.dart';
import '../../features/transactions/data/dispute_repository.dart';
import '../../features/transactions/data/transactions_repository.dart';
import '../../features/transactions/screens/transaction_detail_screen.dart';
import '../../features/transactions/screens/transaction_history_screen.dart';
import '../../features/role_selection/screens/role_selection_screen.dart';
import '../../features/home_feed/screens/home_feed_screen.dart';
import '../../features/host_dashboard/data/host_dashboard_repository.dart';
import '../../features/host_dashboard/screens/host_dashboard_screen.dart';
import '../../features/push_notifications/data/push_notification_repository.dart';
import '../../features/push_notifications/data/push_notification_service.dart';
import '../../features/wallet/data/wallet_repository.dart';
import '../../features/wallet/screens/payout_settings_screen.dart';
import '../../features/wallet/screens/wallet_screen.dart';
import '../api/api_client.dart';
import '../auth/session_store.dart';
import '../config/env.dart';
import '../theme/app_motion.dart';
import 'app_shell.dart';
import 'route_names.dart';

// TODO: replace with real DI (e.g. Provider/Riverpod) once a shared
// composition root exists; this is a minimal, additive wiring so each
// feature's routes are independently functional. Base URL comes from
// AppConfig.apiBaseUrl (build-time --dart-define-from-file=.env.json),
// never hardcoded.
final ApiClient _listingsApiClient = ApiClient(
  baseUrl: AppConfig.apiBaseUrl,
  sessionStore: SessionStore(),
);
final ListingRepository _listingRepository =
    ListingRepository(_listingsApiClient);
final ShareRepository _shareRepository = ShareRepository(_listingsApiClient);
// FEAT-009 -- shares the same ApiClient as listings/chat, no new base
// config needed since /listings/:id/report and /conversations/:id/report
// are just more /v1 endpoints.
final ReportRepository _reportRepository = ReportRepository(_listingsApiClient);

final SessionStore _rootSessionStore = SessionStore();
final ApiClient _authApiClient = ApiClient(
  baseUrl: AppConfig.apiBaseUrl,
  sessionStore: _rootSessionStore,
);
final AuthRepository _authRepository =
    AuthRepository(_authApiClient, _rootSessionStore);

/// Backs the `/` redirect's persistent-sign-in check (FEAT-001). A stored
/// access token alone isn't proof of a valid session -- it could be
/// expired/revoked -- so this round-trips `GET /v1/auth/me` to confirm it
/// (transparently recovered by ApiClient's refresh-on-401 handling if just
/// the access token had expired). Talks to `_authApiClient.dio` directly
/// rather than through `AuthRepository.getCurrentUser` so the real
/// `DioException` (status code, type) is visible here -- only a genuine
/// 401 (refresh token itself invalid/expired/revoked, since ApiClient
/// already tried and failed to refresh it) counts as "not signed in".
/// Anything else -- offline, a 5xx, a timeout -- optimistically keeps the
/// user signed in rather than bouncing them to `/auth` for what may be a
/// purely transient failure; individual screens already have their own
/// offline/error states once inside the app.
Future<bool> _hasPersistedSession() async {
  final accessToken = await _rootSessionStore.readAccessToken();
  if (accessToken == null) return false;
  try {
    await _authApiClient.dio.get('/v1/auth/me');
    return true;
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) {
      await _rootSessionStore.clear();
      return false;
    }
    return true;
  }
}

final ApiClient _hostAccountApiClient = ApiClient(
  baseUrl: AppConfig.apiBaseUrl,
  sessionStore: SessionStore(),
);
final HostAccountRepository _hostAccountRepository =
    HostAccountRepository(_hostAccountApiClient);

final ApiClient _accountDeletionApiClient = ApiClient(
  baseUrl: AppConfig.apiBaseUrl,
  sessionStore: SessionStore(),
);
final AccountDeletionRepository _accountDeletionRepository =
    AccountDeletionRepository(_accountDeletionApiClient);

final ApiClient _chatApiClient = ApiClient(
  baseUrl: AppConfig.apiBaseUrl,
  sessionStore: SessionStore(),
);
final ChatApi _chatApi = ChatApi(_chatApiClient);
final ChatRepository _chatRepository = ChatRepository(chatApi: _chatApi);

final ApiClient _supportApiClient = ApiClient(
  baseUrl: AppConfig.apiBaseUrl,
  sessionStore: SessionStore(),
);
final SupportRepository _supportRepository = SupportRepository(
  supportApi: SupportApi(_supportApiClient),
  chatApi: _chatApi,
);

final ApiClient _bookingApiClient = ApiClient(
  baseUrl: AppConfig.apiBaseUrl,
  sessionStore: SessionStore(),
);
final BookingApi _bookingApi = BookingApi(_bookingApiClient);

final ApiClient _checkoutApiClient = ApiClient(
  baseUrl: AppConfig.apiBaseUrl,
  sessionStore: SessionStore(),
);
final CheckoutRepository _checkoutRepository =
    CheckoutRepository(_checkoutApiClient);

final ApiClient _transactionsApiClient = ApiClient(
  baseUrl: AppConfig.apiBaseUrl,
  sessionStore: SessionStore(),
);
final TransactionsRepository _transactionsRepository =
    TransactionsRepository(_transactionsApiClient);
final DisputeRepository _disputeRepository =
    DisputeRepository(_transactionsApiClient);

final ApiClient _homeFeedSearchApiClient = ApiClient(
  baseUrl: AppConfig.apiBaseUrl,
  sessionStore: SessionStore(),
);
final SearchRepository _homeFeedSearchRepository =
    SearchRepository(apiClient: _homeFeedSearchApiClient);

final ApiClient _pushNotificationApiClient = ApiClient(
  baseUrl: AppConfig.apiBaseUrl,
  sessionStore: SessionStore(),
);
final PushNotificationRepository _pushNotificationRepository =
    PushNotificationRepository(_pushNotificationApiClient);
final PushNotificationService _pushNotificationService =
    PushNotificationService(repository: _pushNotificationRepository);

final ApiClient _hostDashboardApiClient = ApiClient(
  baseUrl: AppConfig.apiBaseUrl,
  sessionStore: SessionStore(),
);
final HostDashboardRepository _hostDashboardRepository =
    HostDashboardRepository(_hostDashboardApiClient);

final ApiClient _agencyApiClient = ApiClient(
  baseUrl: AppConfig.apiBaseUrl,
  sessionStore: SessionStore(),
);
final AgencyRepository _agencyRepository = AgencyRepository(_agencyApiClient);

final ApiClient _walletApiClient = ApiClient(
  baseUrl: AppConfig.apiBaseUrl,
  sessionStore: SessionStore(),
);
final WalletRepository _walletRepository = WalletRepository(_walletApiClient);

final GoRouter appRouter = GoRouter(
  // screens.md Screen 1 (Sign-Up / Login) documents its own entry point as
  // "App launch (unauthenticated)" -- there is no separate Splash/Onboarding
  // screen in the docs, so app launch always resolves through this single
  // `/` redirect rather than rendering its own placeholder screen, whether
  // or not a session already exists.
  initialLocation: '/',
  // FEAT-001 AC "User can log in and stay logged in across app restarts" --
  // previously every launch (and any stray link to `/`) went straight to
  // `/auth` regardless of whether a session was already stored, silently
  // ignoring that AC. Now checks for a persisted, still-valid session
  // (ApiClient's own refresh-on-401 handles a merely-expired access token,
  // see api_client.dart) and only falls back to `/auth` if there truly
  // isn't one.
  redirect: (context, state) async {
    if (state.uri.path != '/') return null;
    return await _hasPersistedSession() ? '/home' : '/auth';
  },
  routes: [
    // -- Screen 1: Sign-Up / Login (Google / Firebase). Redesigned per
    // FEAT-001's rewrite: a single `/auth` path with no Sign Up / Log In
    // tab distinction anymore -- Google Sign-In, Firebase email/password,
    // and Firebase phone/OTP each resolve whether the identity is new or
    // returning themselves (see AuthScreen/AuthRepository), so the old
    // `?mode=login` query param and its tab-index plumbing no longer apply.
    GoRoute(
      path: '/auth',
      name: RouteNames.auth,
      builder: (context, state) => AuthScreen(repository: _authRepository),
      routes: [
        // Screen 2: Role Selection.
        GoRoute(
          path: 'role',
          name: RouteNames.authRole,
          builder: (context, state) =>
              RoleSelectionScreen(repository: _authRepository),
        ),
        GoRoute(
          path: 'accept-invite',
          name: RouteNames.authAcceptInvite,
          builder: (context, state) => AcceptInviteScreen(
            repository: _authRepository,
            onAccepted: (_) => context.goNamed(RouteNames.home),
          ),
        ),
      ],
    ),

    // -- Screen 3a/3b: Become a Host.
    GoRoute(
      path: '/verification',
      name: RouteNames.verification,
      builder: (context, state) =>
          HostTypeSelectionScreen(repository: _hostAccountRepository),
      routes: [
        GoRoute(
          path: ':hostType',
          name: RouteNames.verificationHostType,
          builder: (context, state) => DocumentSubmissionScreen(
            repository: _hostAccountRepository,
            hostType: hostTypeFromApiValue(state.pathParameters['hostType']!),
          ),
        ),
      ],
    ),

    // -- Screen 7: Create Listing. A sibling of `/listing/:id`, not a
    // child -- declared BEFORE it below so the static "new" segment is
    // never captured by the dynamic `:id` param (go_router matches
    // top-level routes in declaration order, same as nested ones).
    GoRoute(
      path: '/listing/new',
      name: RouteNames.listingNew,
      builder: (context, state) =>
          CreateListingScreen(repository: _listingRepository),
    ),
    // -- Screen 6/6b: Listing Detail + Confirm Booking Details.
    GoRoute(
      path: '/listing/:id',
      name: RouteNames.listingDetail,
      builder: (context, state) => ListingDetailScreen(
        listingId: state.pathParameters['id']!,
        repository: _listingRepository,
        chatRepository: _chatRepository,
        shareRepository: _shareRepository,
        reportRepository: _reportRepository,
      ),
      routes: [
        GoRoute(
          path: 'confirm-booking',
          name: RouteNames.listingConfirmBooking,
          builder: (context, state) => BookingScreen(
            listingId: state.pathParameters['id']!,
            listingRepository: _listingRepository,
            // Fresh controller per visit -- it owns a single booking
            // attempt's countdown/timer state, never shared across
            // different bookings.
            bookingController: BookingController(_bookingApi),
          ),
        ),
        // -- Edit Listing (FEAT-004 AC) -- see edit_listing_screen.dart's
        // header docstring for why this has no screens.md screen number.
        GoRoute(
          path: 'edit',
          name: RouteNames.listingEdit,
          builder: (context, state) => EditListingScreen(
            listingId: state.pathParameters['id']!,
            repository: _listingRepository,
          ),
        ),
      ],
    ),

    // -- Screen 9: Chat Thread. Pushed full-screen (its own AppBar +
    // input bar takes the whole screen per screens.md's layout, no bottom
    // nav coexisting) -- not nested under the Chat tab's `/chat` branch.
    GoRoute(
      path: '/chat/:id',
      name: RouteNames.chatThread,
      builder: (context, state) => ChatThreadScreen(
        conversationId: state.pathParameters['id']!,
        chatRepository: _chatRepository,
        authRepository: _authRepository,
        reportRepository: _reportRepository,
        listingRepository: _listingRepository,
      ),
    ),

    // -- Screen 10/11: Checkout + Payment Confirmation.
    GoRoute(
      path: '/checkout/:transactionId',
      name: RouteNames.checkoutTransaction,
      builder: (context, state) => CheckoutScreen(
        transactionId: state.pathParameters['transactionId']!,
        repository: _checkoutRepository,
      ),
      routes: [
        GoRoute(
          path: 'confirmation',
          name: RouteNames.checkoutConfirmation,
          builder: (context, state) => PaymentConfirmationScreen(
            transactionId: state.pathParameters['transactionId']!,
            repository: _checkoutRepository,
          ),
        ),
      ],
    ),

    // -- Screen 19: Transaction History. Entry points include both
    // Payment Confirmation and Account Settings (Profile tab) -- pushed
    // full-screen from either, not itself a bottom-nav tab (screens.md
    // Screen 4's tab list is Home/Chat/Dashboard/Profile only).
    GoRoute(
      path: '/transactions',
      name: RouteNames.transactions,
      builder: (context, state) => TransactionHistoryScreen(
        transactionsRepository: _transactionsRepository,
        checkoutRepository: _checkoutRepository,
        disputeRepository: _disputeRepository,
        listingRepository: _listingRepository,
      ),
      routes: [
        // Hero destination for the row's `transaction-amount-<id>` tag
        // (screens.md Screen 19 Modernization Notes: shared-element
        // transition into receipt detail). `CustomTransitionPage` pins the
        // route -- and therefore the Hero flight -- to the
        // `sharedElementTransition` duration token instead of go_router's
        // default page-transition duration.
        GoRoute(
          path: ':id',
          name: RouteNames.transactionDetail,
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            transitionDuration: AppDurations.sharedElementTransition,
            reverseTransitionDuration: AppDurations.sharedElementTransition,
            child: TransactionDetailScreen(
              transactionId: state.pathParameters['id']!,
              repository: _checkoutRepository,
              listingRepository: _listingRepository,
            ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
                    FadeTransition(opacity: animation, child: child),
          ),
        ),
      ],
    ),

    // -- FEAT-029: General In-App Support / Help. Not a screens.md-numbered
    // mobile screen (only the Admin Web Console side is documented,
    // Screen 26) -- entry point is Account Settings' "Help & Support" row.
    GoRoute(
      path: '/support',
      name: RouteNames.support,
      builder: (context, state) => SupportScreen(
        supportRepository: _supportRepository,
        authRepository: _authRepository,
      ),
    ),

    // -- Screen 5: Search Results. Deliberately NOT a shell branch --
    // screens.md Screen 4's Layout: "Search is intentionally not a
    // persistent tab; it's reached via the prominent search entry field"
    // on Home Feed. Pushed full-screen (no bottom nav) from that field,
    // same as Listing Detail/Checkout/etc.
    GoRoute(
      path: '/search',
      name: RouteNames.search,
      builder: (context, state) =>
          SearchResultsScreen(initialQuery: state.uri.queryParameters['q']),
    ),

    // -- Screen 20: Saved Searches (FEAT-023). Entry points: Home Feed,
    // Search Results ("Save this search"); pushed full-screen, same
    // non-tab treatment as Search Results above.
    GoRoute(
      path: '/search/saved',
      name: RouteNames.savedSearches,
      builder: (context, state) => const SavedSearchesScreen(),
    ),

    // -- Screen 14: Portfolio List View (agency).
    GoRoute(
      path: '/agency/listings',
      name: RouteNames.agencyPortfolio,
      builder: (context, state) =>
          PortfolioListScreen(repository: _agencyRepository),
      routes: [
        // -- Screen 16: Lead Analytics View.
        GoRoute(
          path: ':id/analytics',
          name: RouteNames.agencyListingAnalytics,
          builder: (context, state) => LeadAnalyticsScreen(
            listingId: state.pathParameters['id']!,
            repository: _agencyRepository,
          ),
        ),
      ],
    ),

    // -- Screen 15: Unassigned Leads Inbox (agency).
    GoRoute(
      path: '/agency/leads',
      name: RouteNames.agencyLeads,
      builder: (context, state) =>
          UnassignedLeadsInboxScreen(repository: _agencyRepository),
    ),

    // -- FEAT-012: Team management (invite/list team members).
    GoRoute(
      path: '/agency/team',
      name: RouteNames.agencyTeam,
      builder: (context, state) =>
          TeamManagementScreen(repository: _agencyRepository),
    ),

    // -- FEAT-044: Host/Agency Virtual Wallet. Entry point: Account
    // Settings (host/agency roles only). Pushed full-screen, same
    // non-tab treatment as Transaction History.
    GoRoute(
      path: '/wallet',
      name: RouteNames.wallet,
      builder: (context, state) => WalletScreen(repository: _walletRepository),
      routes: [
        // -- FEAT-045: Payout Settings.
        GoRoute(
          path: 'payout-settings',
          name: RouteNames.walletPayoutSettings,
          builder: (context, state) =>
              PayoutSettingsScreen(repository: _walletRepository),
        ),
      ],
    ),

    // -- Screens 4/8/12/21: the 4 bottom-nav tab roots, per screens.md
    // Screen 4's "BottomNavigationBar with tabs: Home, Chat, Dashboard
    // (Host/Agency, shown per role), Profile". Branch order here MUST
    // match app_shell.dart's _visibleBranches index mapping (0=Home,
    // 1=Chat, 2=Dashboard, 3=Profile).
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => AppShell(
          navigationShell: navigationShell, authRepository: _authRepository),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              name: RouteNames.home,
              builder: (context, state) => HomeFeedScreen(
                searchRepository: _homeFeedSearchRepository,
                pushNotificationService: _pushNotificationService,
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/chat',
              name: RouteNames.chat,
              builder: (context, state) => ChatInboxScreen(
                chatRepository: _chatRepository,
                authRepository: _authRepository,
                listingRepository: _listingRepository,
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/host',
              name: RouteNames.host,
              builder: (context, state) => HostDashboardScreen(
                dashboardRepository: _hostDashboardRepository,
                hostAccountRepository: _hostAccountRepository,
                authRepository: _authRepository,
              ),
            ),
          ],
        ),
        // -- Screen 13: Agency Dashboard. Separate branch from `/host` above
        // (rather than reusing it) since an agency account's Dashboard tab
        // shows agency-portfolio metrics, not the individual-host listing
        // list -- app_shell.dart's `_showsAgencyTab`/`_visibleBranches`
        // picks exactly one of the two per role, never both.
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/agency',
              name: RouteNames.agency,
              builder: (context, state) =>
                  AgencyDashboardScreen(repository: _agencyRepository),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              name: RouteNames.settings,
              builder: (context, state) => AccountSettingsScreen(
                authRepository: _authRepository,
                accountDeletionRepository: _accountDeletionRepository,
                pushNotificationRepository: _pushNotificationRepository,
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);
