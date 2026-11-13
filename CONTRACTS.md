# De-Duke: API Contracts

All endpoints live under `/v1` from first release. Contracts below are **Frozen**: they were derived from the implemented Backend API Service (`apps/backend/app/api/v1/`), so the code is the contract. A change after Frozen is a change request: update the contract, mark it `Frozen (revision N)`, and re-dispatch both the backend and frontend owners.

Auth convention: consumer roles (Guest, Host, Agency) send a De-Duke bearer session token issued by `POST /v1/auth/firebase-exchange`. Staff/Admin send the backend-managed bearer token from `POST /v1/auth/login`. Internal roles are enforced server-side per endpoint.

## Auth & Account

### C-001: POST /v1/auth/firebase-exchange
Status: Frozen
Description: Exchange a verified Firebase ID token for a De-Duke session token. Creates the User on first sign-in (FEAT-001). 409 if the resolved email/phone collides with an existing password-provider account (see FEAT-040).
Auth: None (Firebase token proves identity).
Request: `{ "firebaseIdToken": "string" }`
Response 200: `{ "accessToken": "string", "refreshToken": "string", "tokenType": "bearer", "expiresIn": 3600, "user": { "id", "fullName", "email", "role", "authProvider", "isNewUser" } }`
Errors: 401 (invalid/expired Firebase token), 409 (identity already associated with a password-provider account)

### C-002: POST /v1/auth/login
Status: Frozen
Description: Staff/Admin email + password login (FEAT-033).
Auth: None.
Request: `{ "email": "string", "password": "string" }`
Response 200: `AuthTokenResponse` (same shape as C-001).
Errors: 401 (bad credentials)

### C-003: POST /v1/auth/refresh
Status: Frozen
Description: Rotate the access token using a refresh token.
Auth: Bearer refresh token.
Request: `{ "refreshToken": "string" }`
Response 200: `AuthTokenResponse`.

### C-004: POST /v1/auth/logout
Status: Frozen
Description: Revoke the current session. 204.
Auth: Bearer.

### C-005: POST /v1/auth/forgot-password
Status: Frozen
Description: Send a password reset email (Staff/Admin). 202.
Auth: None.
Request: `{ "email": "string" }`

### C-006: POST /v1/auth/reset-password
Status: Frozen
Description: Set a new password with the emailed token. 204.
Request: `{ "token": "string", "newPassword": "string" }`

### C-007: POST /v1/auth/accept-invite
Status: Frozen
Description: An invited staff member or agency team member sets their password and activates the account (FEAT-033/FEAT-012).
Request: `{ "token": "string", "fullName": "string", "password": "string" }`
Response 200: `AuthTokenResponse`.

### C-008: POST /v1/auth/link-firebase-identity
Status: Frozen
Description: Attach a Firebase identity to an existing password-provider account (FEAT-040). Proves both sides: existing bearer session + live Firebase token.
Auth: Bearer (password-provider account only).
Request: `{ "firebaseIdToken": "string" }`
Response 200: `CurrentUserResponse`.
Errors: 409 (identity already linked to a different account), 400 (firebase-provider account)

### C-009: DELETE /v1/auth/link-firebase-identity
Status: Frozen
Description: Unlink the Firebase identity; password remains. 204.
Auth: Bearer.

### C-010: POST /v1/auth/change-password
Status: Frozen
Description: Logged-in password change for Staff/Admin (FEAT-041). Invalidates other sessions. 204.
Auth: Bearer.
Request: `{ "currentPassword": "string", "newPassword": "string" }`

### C-011: GET /v1/auth/me · GET /v1/auth/me/notification-preferences · PATCH /v1/auth/me/notification-preferences · PATCH /v1/auth/me/role
Status: Frozen
Description: Current user, per-category push/email preferences (FEAT-022/FEAT-024), and role selection (FEAT-003).
Auth: Bearer.
Response: `CurrentUserResponse`, `NotificationPreferencesResponse`.

### C-012: GET /v1/user/profile · PATCH /v1/user/profile
Status: Frozen
Description: Self-service profile: `fullName` always editable, `email`/`phoneNumber` read-only for firebase-provider accounts (rejected server-side), `profilePhotoUrl` editable for all (FEAT-041). PATCH is multipart (photo + name in one call).
Auth: Bearer.
Response: `UserProfileResponse`.

### C-013: POST /v1/account-deletion/request
Status: Frozen
Description: Request account and data deletion (FEAT-030, NDPA). Explains immediate deletion versus retained records. 201.
Auth: Bearer.

## Host Accounts & Verification

### C-014: GET /v1/host-accounts/me
Status: Frozen
Description: The user's most recent HostAccount status (in_review/verified/rejected) and profile.
Auth: Bearer.
Response: `HostAccountStatusResponse | null`.

### C-015: POST /v1/host-accounts
Status: Frozen
Description: Submit a Become a Host application (FEAT-002). Multipart: photo, bio, and type-specific documents as structured sub-records with explicit ids.
Auth: Bearer.
Response 201: `HostAccountStatusResponse`.
Errors: 409 (another submission in review or verified), 422 (missing required document for host type)

### C-016: PATCH /v1/host-accounts/me
Status: Frozen
Description: Edit bio and/or host photo after verification (FEAT-042). Multipart. Only for verified or rejected hosts.
Auth: Bearer.
Response: `HostAccountStatusResponse`.

### C-017: GET /v1/host-accounts/admin · GET /v1/host-accounts/admin/{host_account_id} · PATCH /v1/host-accounts/admin/{host_account_id}/status
Status: Frozen
Description: Staff/Admin verification queue, submission detail with documents, and Verify/Reject decision with required reason (FEAT-002).
Auth: Bearer, deduke_staff or deduke_admin.
Response: `PaginatedHostAccountQueue`, `HostAccountDetailResponse`, `HostAccountStatusResponse`.

## Listings

### C-018: GET /v1/listings
Status: Frozen
Description: List listings (guest search result support and staff/admin catalog via FEAT-046; staff filter uses this endpoint with internal-role auth).
Auth: Optional (public browse) / Bearer for mine and staff filters.
Query: `mine`, `status`, `listing_type`, `cursor`, `limit`.
Response: `ListingListResponse`.

### C-019: POST /v1/listings
Status: Frozen
Description: Create a listing (FEAT-004/FEAT-005). Multipart with structured sub-records for media and commercial rooms. Professional-type hosts auto-approve; Owner-type listings enter Under Review (FEAT-008).
Auth: Bearer, verified host account.
Request: `{ "listingType": "commercial|shortlet", "title", "description", "price", "location": {...}, "commercial": {...} | "shortlet": {...}, "media": [ { "id", "isPrimary", "displayOrder" } ], "rooms": [ { "id", "level", "width", "length", "displayOrder" } ] }` + file fields.
Response 201: `ListingOut`.
Errors: 403 (unverified host), 422 (validation)

### C-020: GET /v1/listings/{listing_id} · PATCH /v1/listings/{listing_id}
Status: Frozen
Description: Listing detail (includes host bio/photo/host type per FEAT-042) and edit. Edits apply going forward only.
Auth: GET optional, PATCH Bearer (owner).
Response: `ListingOut`.

### C-021: POST /v1/listings/{listing_id}/media
Status: Frozen
Description: Add or replace listing media with explicit per-record ids (structured upload contract).
Auth: Bearer, owner.
Response 201: `ListingOut`.

### C-022: GET /v1/listings/{listing_id}/availability
Status: Frozen
Description: Availability for shortlet dates / lease possession windows, honoring paid bookings and active holds.
Auth: Bearer.
Query: `start_date`, `end_date`.
Response: `AvailabilityOut`.

### C-023: GET /v1/search/listings
Status: Frozen
Description: Geospatial + filtered + semantic search (FEAT-006/FEAT-007/FEAT-031). Cursor pagination, proximity ranking, distance per result. Semantic degradation flag on embedding timeout.
Auth: Optional.
Query: `lat`, `lng`, `radius_km`, `filters` (price, subtype, deal type, bathrooms, size, amenities, legal_documents, verified_only), `sort`, `cursor`.
Response: `SearchResponse` with `degraded` info when semantic ranking fell back.

## Bookings, Checkout & Commission

### C-024: POST /v1/bookings/confirm
Status: Frozen
Description: Confirm booking details and create a time-limited hold (default 15 min, FEAT-032). Snapshots the full commission breakdown (FEAT-014) before checkout.
Auth: Bearer.
Request: `{ "listingId", "startDate", "endDate" }`
Response 201: `BookingHoldResponse` with countdown and breakdown.
Errors: 409 (dates held/booked), 410 (hold already expired on retry)

### C-025: GET /v1/bookings/{transaction_id}
Status: Frozen
Description: Current hold state for the transaction.
Auth: Bearer.
Response: `BookingHoldResponse`.

### C-026: POST /v1/checkout/initiate
Status: Frozen
Description: Initiate Paystack checkout against the persisted gross amount. Requires an active hold; carries a client-generated idempotency key.
Auth: Bearer.
Request: `{ "transactionId", "idempotencyKey" }`
Response: `InitiateCheckoutResponse` (Paystack authorization URL / reference).
Errors: 400 (hold expired or no hold), 409 (duplicate idempotency key)

### C-027: POST /v1/checkout/webhook
Status: Frozen
Description: Paystack webhook. Signature-verified; only here is a booking marked paid (`payment_received`). Never trusted from client reports.
Auth: Paystack signature.

### C-028: GET /v1/transactions · GET /v1/transactions/{transaction_id} · GET /v1/transactions/{transaction_id}/commission
Status: Frozen
Description: Transaction history, detail, and the persisted commission breakdown (FEAT-015/FEAT-014).
Auth: Bearer.
Response: `TransactionListResponse`, `TransactionDetail`, `CommissionBreakdown`.

### C-029: GET /v1/commission/{transaction_type}/{fee_type}/current · GET /v1/commission/{transaction_type}/{fee_type} · POST /v1/commission
Status: Frozen
Description: Public current-rate preview (any authenticated user), per-pair history (Admin), and rate change (Admin only, FEAT-027).
Auth: GET current Bearer; history/change deduke_admin.
Response: `CommissionRateResponse`, `CommissionRateHistoryResponse`.
Errors: 403 (Staff cannot change), 422 (rate outside 0-100)

## Wallet, Escrow & Payouts

### C-030: GET /v1/wallet/admin/releasable · POST /v1/wallet/admin/{transaction_id}/release
Status: Frozen
Description: Release Funds queue and manual escrow release (FEAT-043). Atomic: transaction → released_to_wallet, wallet credit, WalletTransaction. Open disputes hard-block release.
Auth: Bearer, deduke_admin only (Staff read-only on queue).
Errors: 400 (open dispute), 409 (already released)

### C-031: GET /v1/wallet · GET /v1/wallet/transactions
Status: Frozen
Description: Wallet balance (derived cache) and immutable ledger (FEAT-044).
Auth: Bearer (host/agency).
Response: `WalletOut`, `WalletTransactionListResponse`.

### C-032: GET /v1/wallet/banks · GET /v1/wallet/payout-settings · PUT /v1/wallet/payout-settings
Status: Frozen
Description: Bank list, current payout settings, and save with Paystack account resolution (FEAT-045). Requires verified HostAccount to access.
Auth: Bearer.
Response: `BankOptionOut[]`, `PayoutSettingsResponse`.

### C-033: POST /v1/wallet/withdrawals · GET /v1/wallet/withdrawals
Status: Frozen
Description: Request a withdrawal (debited immediately, `processing`) fulfilled automatically via Paystack Transfer; and withdrawal list. No Admin approval (FEAT-045).
Auth: Bearer, verified PayoutSettings required.
Response 201: `WithdrawalResponse`.

## Chat

### C-034: POST /v1/chat/token · POST /v1/chat/sync-claims · GET /v1/chat/users
Status: Frozen
Description: Mint scoped custom Firestore tokens for Staff/Admin; sync consumer custom claims; chat participant lookup.
Auth: Bearer.
Response: `ChatTokenResponse`, `ChatUserOut[]`.

### C-035: POST /v1/chat/conversations/{conversation_id}/notify · POST /v1/support/conversations/{conversation_id}/notify
Status: Frozen
Description: Trigger push notification for new messages in a listing conversation or a general support conversation (FEAT-010/FEAT-029).
Auth: Bearer.
Response 202.

## Agency

### C-036: GET /v1/agency/summary · GET /v1/agency/listings · POST /v1/agency/listings/bulk-action
Status: Frozen
Description: Agency portfolio aggregates, portfolio list with agent/client tags, and bulk actions (archive/relist) (FEAT-018).
Auth: Bearer, agency role.
Response: `AgencySummaryOut`, `AgencyListingItemOut[]`, `BulkListingActionResponse`.

### C-037: GET /v1/agency/team · GET /v1/agency/leads · PATCH /v1/agency/leads/{lead_id}/assign · GET /v1/agency/listings/{listing_id}/analytics
Status: Frozen
Description: Team members, lead queue, assignment (logged), and per-listing analytics (FEAT-012/FEAT-019).
Auth: Bearer, agency role.
Response: `TeamMemberOut[]`, `LeadOut[]`, `ListingAnalyticsOut`.

## Admin Operations

### C-038: GET /v1/moderation/queue · POST /v1/moderation/{listing_id}/approve · POST /v1/moderation/{listing_id}/ban
Status: Frozen
Description: Moderation queue and approve/ban with required reason (FEAT-025/FEAT-008).
Auth: Bearer, deduke_staff or deduke_admin.
Response: `ModerationQueueItemOut[]`, `ModerationDecisionOut`.

### C-039: GET /v1/disputes · POST /v1/disputes · GET /v1/disputes/{dispute_id} · PATCH /v1/disputes/{dispute_id}/assign · PATCH /v1/disputes/{dispute_id}/resolve
Status: Frozen
Description: Dispute raise (user) and review/assign/resolve with refund (staff) (FEAT-026). Supports `listing_id` filter for FEAT-046 deep links.
Auth: POST Bearer (user); admin endpoints deduke_staff/admin.
Response: `DisputeListItemOut[]` (includes `listing_id`), `DisputeDetailOut`.

### C-040: GET /v1/staff-accounts · POST /v1/staff-accounts/invite · POST /v1/staff-accounts/{user_id}/deactivate · /reactivate · /promote · /demote
Status: Frozen
Description: Staff account management (FEAT-033). Last-admin guard enforced server-side.
Auth: Bearer, deduke_admin.
Response: `StaffAccountOut[]`, `InviteStaffResponse`, `StaffActionResponse`.

### C-041: GET /v1/admin/reports · POST /v1/admin/reports/{report_id}/resolve · /dismiss · POST /v1/listings/{listing_id}/report · POST /v1/conversations/{conversation_id}/report
Status: Frozen
Description: In-app reporting (FEAT-009): guest-facing report actions and the staff/admin report queue merged into moderation.
Auth: POST report Bearer (user); admin endpoints deduke_staff/admin.
Response: `ReportListResponse`, `ReportOut`.

### C-042: GET /v1/analytics/operations · GET /v1/analytics/business
Status: Frozen
Description: Operations dashboard (Staff + Admin) and business/revenue dashboard (Admin only) from the aggregate store (FEAT-034/FEAT-035).
Auth: Bearer, deduke_staff (operations) / deduke_admin (business).
Response: `OperationsDashboardOut`, `BusinessDashboardOut`.

## Shareable Summary

### C-043: POST /v1/listings/{listing_id}/share · DELETE /v1/listings/{listing_id}/share/{share_token} · GET /v1/share/{share_token}
Status: Frozen
Description: Generate, revoke, and publicly view a shareable listing summary without login (FEAT-020). Banned listings never render.
Auth: generate/revoke Bearer; external view unauthenticated.
Response: `ShareRevokeOut`, `SharedListingSummaryOut | ShareStatusOut`.