/// Route skeleton -- go_router configuration with placeholder screens.
/// Feature subagents register their real screens here in Phase B; this file
/// stays a shared module (read/extend, do not restructure without
/// coordinating across subagents to avoid navigation merge conflicts).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/search/screens/search_results_screen.dart';

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
    GoRoute(path: '/', builder: (context, state) => const _PlaceholderScreen(routeName: 'Splash/Onboarding')),
    GoRoute(path: '/auth/login', builder: (context, state) => const _PlaceholderScreen(routeName: 'Login')),
    GoRoute(path: '/auth/signup', builder: (context, state) => const _PlaceholderScreen(routeName: 'Sign Up')),
    GoRoute(path: '/become-host', builder: (context, state) => const _PlaceholderScreen(routeName: 'Become a Host')),
    GoRoute(path: '/home', builder: (context, state) => const _PlaceholderScreen(routeName: 'Home / Discovery')),
    GoRoute(
      path: '/search',
      builder: (context, state) => SearchResultsScreen(initialQuery: state.uri.queryParameters['q']),
    ),
    GoRoute(path: '/listings/:id', builder: (context, state) => const _PlaceholderScreen(routeName: 'Listing Detail')),
    GoRoute(path: '/listings/create', builder: (context, state) => const _PlaceholderScreen(routeName: 'Create Listing')),
    GoRoute(path: '/chat/:conversationId', builder: (context, state) => const _PlaceholderScreen(routeName: 'Chat Conversation')),
    GoRoute(path: '/booking/:listingId', builder: (context, state) => const _PlaceholderScreen(routeName: 'Booking Confirmation')),
    GoRoute(path: '/checkout/:transactionId', builder: (context, state) => const _PlaceholderScreen(routeName: 'Checkout')),
    GoRoute(path: '/transactions', builder: (context, state) => const _PlaceholderScreen(routeName: 'Transaction History')),
    GoRoute(path: '/account-settings', builder: (context, state) => const _PlaceholderScreen(routeName: 'Account Settings')),
  ],
);
