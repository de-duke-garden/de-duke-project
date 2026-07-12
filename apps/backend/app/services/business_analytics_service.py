"""Business & Revenue metrics -- FEAT-035 (Business & Revenue Analytics
Dashboard, Admin only). Same MVP-live-query-instead-of-a-real-aggregate-
store caveat as ops_analytics_service.py -- see that module's header
docstring for the full rationale; not repeated here.

Two metrics from FEAT-035's acceptance criteria are explicitly NOT
computed here, because the features they depend on don't exist yet in
this codebase -- never fabricated:
  - Leakage rate (chat-to-payment conversion, FEAT-016) -- FEAT-016 is a
    Phase 3 feature (Off-Platform Payment Leakage Mitigation) that
    doesn't exist yet; there's no signal in the current schema for "a
    chat led to an off-platform payment instead of an on-platform one."
  - Agency Tier conversion/churn -- the Agency Tier subscription itself
    (monetization.md) launches in Phase 3 alongside FEAT-012/FEAT-019;
    there is no subscription/billing-tier entity in the schema yet.
Both keys are present in get_business_dashboard's return shape, set to
None, so the Admin console can render an honest "not yet available" state
instead of a missing key or a fabricated zero.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.host_account import HostAccount
from app.models.listing import Listing
from app.models.transaction import Transaction
from app.models.user import User


async def signups_by_role(
    session: AsyncSession, *, since: datetime | None = None
) -> dict[str, int]:
    stmt = select(User.role, func.count()).group_by(User.role)
    if since is not None:
        stmt = stmt.where(User.created_at >= since)
    rows = (await session.execute(stmt)).all()
    return dict(rows)


async def host_verification_submissions_by_type(
    session: AsyncSession, *, since: datetime | None = None
) -> dict[str, int]:
    stmt = select(HostAccount.host_type, func.count()).group_by(HostAccount.host_type)
    if since is not None:
        stmt = stmt.where(HostAccount.created_at >= since)
    rows = (await session.execute(stmt)).all()
    return dict(rows)


async def active_listings_breakdown(session: AsyncSession) -> dict[str, Any]:
    by_type_stmt = select(Listing.listing_type, func.count()).group_by(Listing.listing_type)
    by_status_stmt = select(Listing.status, func.count()).group_by(Listing.status)
    by_city_stmt = (
        select(Listing.location_city, func.count())
        .where(Listing.status == "active")
        .group_by(Listing.location_city)
    )

    by_type = dict((await session.execute(by_type_stmt)).all())
    by_status = dict((await session.execute(by_status_stmt)).all())
    by_city = dict((await session.execute(by_city_stmt)).all())

    return {"by_type": by_type, "by_status": by_status, "by_city": by_city}


async def conversion_funnel(session: AsyncSession) -> dict[str, Any]:
    """search -> view -> inquiry -> booking (screens.md Screen 30 AC).
    "search" has no count here -- unlike view_count/inquiry_count, search
    activity was never persisted to the Primary Database (it's exactly
    the kind of event analytics_service.track_event now captures, but
    that platform is still an unconfigured no-op stub -- see
    analytics_service.py). The other three steps use existing Listing/
    Transaction columns and are real counts, not estimates."""
    totals_stmt = select(
        func.coalesce(func.sum(Listing.view_count), 0),
        func.coalesce(func.sum(Listing.inquiry_count), 0),
    )
    total_views, total_inquiries = (await session.execute(totals_stmt)).one()

    total_bookings = (await session.execute(select(func.count()).select_from(Transaction))).scalar_one()

    return {
        "search": None,  # not yet available -- see docstring
        "view": total_views,
        "inquiry": total_inquiries,
        "booking": total_bookings,
    }


async def revenue_breakdown(session: AsyncSession) -> dict[str, Any]:
    """Gross Transaction Value, commission revenue, and take rate by
    transaction type (screens.md Screen 30 AC) -- only counts `succeeded`
    transactions, since a held/failed/expired transaction never actually
    generated revenue."""
    stmt = (
        select(
            Transaction.transaction_type,
            func.coalesce(func.sum(Transaction.gross_amount), 0),
            func.coalesce(func.sum(Transaction.commission_amount), 0),
        )
        .where(Transaction.status == "succeeded")
        .group_by(Transaction.transaction_type)
    )
    rows = (await session.execute(stmt)).all()

    breakdown: dict[str, dict[str, float]] = {}
    total_gtv = 0.0
    total_commission = 0.0
    for transaction_type, gross, commission in rows:
        take_rate = (commission / gross) if gross else 0.0
        breakdown[transaction_type] = {
            "gross_transaction_value": gross,
            "commission_revenue": commission,
            "take_rate": take_rate,
        }
        total_gtv += gross
        total_commission += commission

    return {
        "by_transaction_type": breakdown,
        "total_gross_transaction_value": total_gtv,
        "total_commission_revenue": total_commission,
        "overall_take_rate": (total_commission / total_gtv) if total_gtv else 0.0,
    }


async def get_business_dashboard(
    session: AsyncSession, *, since: datetime | None = None
) -> dict[str, Any]:
    return {
        "signups_by_role": await signups_by_role(session, since=since),
        "host_verification_submissions_by_type": await host_verification_submissions_by_type(
            session, since=since
        ),
        "active_listings": await active_listings_breakdown(session),
        "conversion_funnel": await conversion_funnel(session),
        "revenue": await revenue_breakdown(session),
        # Not yet available -- see module header docstring. Never fabricated.
        "leakage_rate": None,
        "agency_tier": None,
    }
