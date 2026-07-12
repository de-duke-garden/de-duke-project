"""Versioned API router aggregation -- all endpoints live under /v1 from
first release (AGENTS.md, architecture.md API Contract Stability)."""

from fastapi import APIRouter

from app.api.v1 import (
    account_deletion,
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
    search,
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
