"""Versioned API router aggregation -- all endpoints live under /v1 from
first release (AGENTS.md, architecture.md API Contract Stability)."""

from fastapi import APIRouter

from app.api.v1 import (
    account_deletion,
    agency,
    analytics,
    auth,
    bookings,
    chat_auth,
    checkout,
    commission,
    disputes,
    host_accounts,
    host_dashboard,
    listings,
    moderation,
    notifications,
    reports,
    saved_searches,
    search,
    share,
    staff_accounts,
    support,
    transactions,
)

router = APIRouter(prefix="/v1")
router.include_router(auth.router, prefix="/auth", tags=["auth"])
router.include_router(host_accounts.router, prefix="/host-accounts", tags=["host-accounts"])
router.include_router(
    account_deletion.router, prefix="/account-deletion", tags=["account-deletion"]
)
router.include_router(listings.router, prefix="/listings", tags=["listings"])
router.include_router(moderation.router, prefix="/moderation", tags=["moderation"])
router.include_router(search.router, prefix="/search", tags=["search"])
# FEAT-023 -- Saved Searches & Listing Alerts. Plural "/searches", distinct
# from search.router's singular "/search" prefix above (owned by a
# parallel Search & Discovery workstream) -- see saved_searches.py's
# module docstring for why.
router.include_router(saved_searches.router, prefix="/searches", tags=["saved-searches"])
router.include_router(chat_auth.router, prefix="/chat", tags=["chat"])
router.include_router(bookings.router, prefix="/bookings", tags=["bookings"])
router.include_router(checkout.router, prefix="/checkout", tags=["checkout"])
router.include_router(transactions.router, prefix="/transactions", tags=["transactions"])
router.include_router(staff_accounts.router, prefix="/staff-accounts", tags=["staff-accounts"])
router.include_router(commission.router, prefix="/commission", tags=["commission"])
router.include_router(host_dashboard.router, prefix="/host", tags=["host-dashboard"])
router.include_router(notifications.router, prefix="/notifications", tags=["notifications"])
router.include_router(disputes.router, prefix="/disputes", tags=["disputes"])
router.include_router(support.router, prefix="/support", tags=["support"])
router.include_router(analytics.router, prefix="/analytics", tags=["analytics"])
router.include_router(agency.router, prefix="/agency", tags=["agency"])
# FEAT-020 -- Shareable Listing Summary. listing_share_router adds
# auth-required generate/revoke endpoints under /listings; public_share_router
# is the unauthenticated-by-design external view under /share/{token}.
router.include_router(share.listing_share_router, prefix="/listings", tags=["listings"])
router.include_router(share.public_share_router, prefix="/share", tags=["share"])
# FEAT-009 -- In-App Reporting. listing_report_router/conversation_report_router
# are the seeker-facing report endpoints; router is the staff/admin-facing
# admin/reports queue, merged into the Moderation Queue by moderation_service.py.
router.include_router(reports.listing_report_router, prefix="/listings", tags=["reports"])
router.include_router(reports.conversation_report_router, prefix="/conversations", tags=["reports"])
router.include_router(reports.router, prefix="/admin/reports", tags=["reports"])
