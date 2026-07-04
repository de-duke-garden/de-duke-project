"""Versioned API router aggregation -- all endpoints live under /v1 from
first release (AGENTS.md, architecture.md API Contract Stability)."""

from fastapi import APIRouter

from app.api.v1 import (
    auth,
    bookings,
    chat_auth,
    checkout,
    commission,
    host_accounts,
    listings,
    moderation,
    search,
    staff_accounts,
    transactions,
)

router = APIRouter(prefix="/v1")
router.include_router(auth.router, prefix="/auth", tags=["auth"])
router.include_router(host_accounts.router, prefix="/host-accounts", tags=["host-accounts"])
router.include_router(listings.router, prefix="/listings", tags=["listings"])
router.include_router(moderation.router, prefix="/moderation", tags=["moderation"])
router.include_router(search.router, prefix="/search", tags=["search"])
router.include_router(chat_auth.router, prefix="/chat", tags=["chat"])
router.include_router(bookings.router, prefix="/bookings", tags=["bookings"])
router.include_router(checkout.router, prefix="/checkout", tags=["checkout"])
router.include_router(transactions.router, prefix="/transactions", tags=["transactions"])
router.include_router(staff_accounts.router, prefix="/staff-accounts", tags=["staff-accounts"])
router.include_router(commission.router, prefix="/commission", tags=["commission"])
