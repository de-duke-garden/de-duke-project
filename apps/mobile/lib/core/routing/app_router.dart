/// Route skeleton -- go_router configuration with placeholder screens.
/// Feature subagents register their real screens here in Phase B; this file
/// stays a shared module (read/extend, do not restructure without
/// coordinating across subagents to avoid navigation merge conflicts).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/screens/auth_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/become_host/data/host_account_models.dart';
import '../../features/become_host/data/host_account_repository.dart';
import '../../features/become_host/screens/document_submission_screen.dart';
import '../../features/chat/data/chat_api.dart';
import '../../features/chat/data/chat_repository.dart';
import '../../features/chat/screens/chat_inbox_screen.dart';
import '../../features/chat/screens/chat_thread_screen.dart';
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
import '../../features/listings/screens/listing_detail_screen.dart';
import '../../features/search/screens/search_results_screen.dart';
import '../../features/transactions/data/transactions_repository.dart';
import '../../features/transactions/screens/transaction_history_screen.dart';
import '../api/api_client.dart';
import '../auth/session_store.dart';
import '../config/env.dart';

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

final ApiClient _authApiClient = ApiClient(
  baseUrl: AppConfig.apiBaseUrl,
  sessionStore: SessionStore(),
);
final AuthRepository _authRepository =
    AuthRepository(_authApiClient, SessionStore());

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
final ChatRepository _chatRepository =
    ChatRepository(chatApi: ChatApi(_chatApiClient));

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

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.routeName});

  final String routeName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text('$routeName -- not yet implemented')),
    );
  }
}

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
        path: '/',
        builder: (context, state) =>
            const _PlaceholderScreen(routeName: 'Splash/Onboarding')),
    GoRoute(
      path: '/auth/login',
      builder: (context, state) =>
          AuthScreen(repository: _authRepository, initialTabIndex: 1),
    ),
    GoRoute(
      path: '/auth/signup',
      builder: (context, state) =>
          AuthScreen(repository: _authRepository, initialTabIndex: 0),
    ),
    GoRoute(
      path: '/auth/forgot-password',
      builder: (context, state) =>
          ForgotPasswordScreen(repository: _authRepository),
    ),
    GoRoute(
      path: '/become-host',
      builder: (context, state) =>
          HostTypeSelectionScreen(repository: _hostAccountRepository),
    ),
    GoRoute(
      path: '/become-host/:hostType',
      builder: (context, state) => DocumentSubmissionScreen(
        repository: _hostAccountRepository,
        hostType: hostTypeFromApiValue(state.pathParameters['hostType']!),
      ),
    ),
    GoRoute(
        path: '/home',
        builder: (context, state) =>
            const _PlaceholderScreen(routeName: 'Home / Discovery')),
    GoRoute(
      path: '/search',
      builder: (context, state) =>
          SearchResultsScreen(initialQuery: state.uri.queryParameters['q']),
    ),
    GoRoute(
      path: '/listings/:id',
      builder: (context, state) => ListingDetailScreen(
        listingId: state.pathParameters['id']!,
        repository: _listingRepository,
      ),
    ),
    GoRoute(
      path: '/listings/create',
      builder: (context, state) =>
          CreateListingScreen(repository: _listingRepository),
    ),
    GoRoute(
      path: '/chat',
      builder: (context, state) => ChatInboxScreen(
        chatRepository: _chatRepository,
        authRepository: _authRepository,
      ),
    ),
    GoRoute(
      path: '/chat/:conversationId',
      builder: (context, state) => ChatThreadScreen(
        conversationId: state.pathParameters['conversationId']!,
        chatRepository: _chatRepository,
        authRepository: _authRepository,
      ),
    ),
    GoRoute(
      path: '/booking/:listingId',
      builder: (context, state) => BookingScreen(
        listingId: state.pathParameters['listingId']!,
        listingRepository: _listingRepository,
        // Fresh controller per visit -- it owns a single booking attempt's
        // countdown/timer state, never shared across different bookings.
        bookingController: BookingController(_bookingApi),
      ),
    ),
    GoRoute(
      path: '/checkout/:transactionId',
      builder: (context, state) => CheckoutScreen(
        transactionId: state.pathParameters['transactionId']!,
        repository: _checkoutRepository,
      ),
    ),
    GoRoute(
      path: '/checkout/:transactionId/confirmation',
      builder: (context, state) => PaymentConfirmationScreen(
        transactionId: state.pathParameters['transactionId']!,
        repository: _checkoutRepository,
      ),
    ),
    GoRoute(
      path: '/transactions',
      builder: (context, state) => TransactionHistoryScreen(
        transactionsRepository: _transactionsRepository,
        checkoutRepository: _checkoutRepository,
      ),
    ),
    GoRoute(
      path: '/account-settings',
      builder: (context, state) => AccountSettingsScreen(
        authRepository: _authRepository,
        accountDeletionRepository: _accountDeletionRepository,
      ),
    ),
  ],
);
