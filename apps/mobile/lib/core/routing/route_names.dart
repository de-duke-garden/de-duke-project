/// Centralized go_router route *names* (as opposed to raw path strings).
///
/// Every `GoRoute`/`StatefulShellBranch` route in `app_router.dart` is
/// registered with a `name:` drawn from here, and every navigation call
/// site (`context.goNamed`/`context.pushNamed`) uses these constants
/// instead of hand-typing (and re-interpolating) path strings. This means
/// a route's path segment can change in exactly one place (app_router.dart)
/// without hunting down every `context.go('/listing/$id...')` call across
/// feature screens.
///
/// Keep this file name-only (no path strings, no widget imports) so it can
/// be imported from any feature screen without pulling in the router's own
/// dependency graph.
abstract final class RouteNames {
  // -- Screen 1: Sign-Up / Login.
  static const auth = 'auth';

  // -- Screen 2: Role Selection (child of /auth).
  static const authRole = 'authRole';

  // -- Accept Invite (child of /auth) -- FEAT-012/FEAT-033 invite flows.
  // (Forgot Password was removed here -- FEAT-001's Firebase rewrite moved
  // consumer password reset entirely into Firebase's own client-side
  // "forgot password" email flow; see AuthRepository.
  // sendFirebasePasswordResetEmail. Staff/Admin reset via the Admin Web
  // Console, a separate app.)
  static const authAcceptInvite = 'authAcceptInvite';

  // -- Screen 3a: Become a Host / verification type picker.
  static const verification = 'verification';

  // -- Screen 3b: Document Submission (child of /verification).
  static const verificationHostType = 'verificationHostType';

  // -- Screen 7: Create Listing.
  static const listingNew = 'listingNew';

  // -- Screen 6: Listing Detail.
  static const listingDetail = 'listingDetail';

  // -- Screen 6b: Confirm Booking Details (child of listing detail).
  static const listingConfirmBooking = 'listingConfirmBooking';

  // -- Edit Listing (child of listing detail; FEAT-004 AC "edit ... or
  // unpublish an existing listing" -- no dedicated screens.md screen
  // number exists for this).
  static const listingEdit = 'listingEdit';

  // -- Screen 9: Chat Thread.
  static const chatThread = 'chatThread';

  // -- Screen 10: Checkout.
  static const checkoutTransaction = 'checkoutTransaction';

  // -- Screen 11: Payment Confirmation (child of checkout).
  static const checkoutConfirmation = 'checkoutConfirmation';

  // -- Screen 19: Transaction History.
  static const transactions = 'transactions';

  // -- Transaction Detail / Receipt (child of transactions; Hero
  // destination from Transaction History's row, modeled on Screen 11
  // Payment Confirmation).
  static const transactionDetail = 'transactionDetail';

  // -- FEAT-029: General In-App Support / Help.
  static const support = 'support';

  // -- Screen 5: Search Results.
  static const search = 'search';

  // -- Screen 20: Saved Searches (FEAT-023).
  static const savedSearches = 'savedSearches';

  // -- Bottom-nav tab roots (Screens 4/8/12/21).
  static const home = 'home';
  static const chat = 'chat';
  static const host = 'host';
  static const settings = 'settings';

  // -- Screen 13: Agency Dashboard (bottom-nav tab root for agency accounts).
  static const agency = 'agency';

  // -- Screen 14: Portfolio List View.
  static const agencyPortfolio = 'agencyPortfolio';

  // -- Screen 15: Unassigned Leads Inbox.
  static const agencyLeads = 'agencyLeads';

  // -- Screen 16: Lead Analytics View (child of Portfolio List View / Listing Detail).
  static const agencyListingAnalytics = 'agencyListingAnalytics';

  // -- Team management (FEAT-012: invite/list team members).
  static const agencyTeam = 'agencyTeam';
}
