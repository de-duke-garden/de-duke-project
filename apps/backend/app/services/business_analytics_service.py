"""Business & Revenue metrics -- FEAT-035 (Business & Revenue Analytics
Dashboard, Admin only). Same MVP-live-query-instead-of-a-real-aggregate-
store caveat as ops_analytics_service.py -- see that module's header
docstring for the full rationale; not repeated here.

Leakage rate (FEAT-016, now implemented as of Phase 3) is computed below --
see `leakage_rate`'s own docstring for the exact (necessarily approximate)
definition used, since the platform cannot literally observe an
off-platform payment.

Note: an earlier revision of this dashboard also carried an "Agency Tier
conversion/churn" placeholder (always None). That metric has been removed
entirely -- monetization.md's roadmap mentions an "Agency Tier
subscription" product, but no such feature has ever been scoped with its
own FEAT-ID, acceptance criteria, or schema entity anywhere in
features.md/schema.md. Per AGENTS.md's "never fabricate requirements"
rule, a metric with no backing feature doesn't belong in this dashboard's
return shape at all -- if/when Agency Tier is actually scoped as a real
feature, this module gains a new function for it then, not a permanent
None placeholder now.
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

    total_bookings = (
        await session.execute(select(func.count()).select_from(Transaction))
    ).scalar_one()

    return {
        "search": None,  # not yet available -- see docstring
        "view": total_views,
        "inquiry": total_inquiries,
        "booking": total_bookings,
    }


async def revenue_breakdown(session: AsyncSession) -> dict[str, Any]:
    """Gross Transaction Value, commission revenue, and take rate by
    transaction type (screens.md Screen 30 AC) -- counts `payment_received`
    and `released_to_wallet` transactions (schema.md's escrow model: both
    mean the guest actually paid; only whether a De-Duke Admin has since
    released the funds to the payee differs), since a held/failed/expired
    transaction never actually generated revenue."""
    stmt = (
        select(
            Transaction.transaction_type,
            func.coalesce(func.sum(Transaction.gross_amount), 0),
            func.coalesce(func.sum(Transaction.commission_amount), 0),
        )
        .where(Transaction.status.in_(("payment_received", "released_to_wallet")))
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


async def leakage_rate(session: AsyncSession) -> float | None:
    """monetization.md's definition: "% of chat conversations showing
    clear booking intent that do not convert to an in-app payment"
    (FEAT-016 AC: "Analytics capture chat-to-payment conversion rate").

    The platform cannot literally observe an off-platform payment (that's
    the whole leakage problem) -- so this is necessarily an approximation
    from the two DB-queryable proxies actually available:
      - Denominator: `Listing.inquiry_count` summed across every listing.
        A chat conversation's creation increments this counter
        (app/services/chat_service.py::create_conversation) -- it is a
        proxy for "chat conversations", not literally "conversations
        showing clear booking intent" (that finer-grained signal -- the
        mobile client's booking-intent keyword heuristic that triggers
        FEAT-016's "Pay safely in-app" nudge -- exists only client-side
        and is never persisted anywhere queryable; see
        chat_thread_screen.dart). Every started chat is at minimum a
        precondition for booking intent, so this is a reasonable, honest
        upper-bound proxy for the denominator, not an exact match to the
        metric's literal wording.
      - Numerator: every `Transaction` row (an in-app payment reaching at
        least `held`/`succeeded` status counts as "converted", since a
        booking hold -- FEAT-032 -- is itself evidence the chat
        conversation led to an in-app checkout attempt, not an off-
        platform arrangement).

    Returns None (not a fabricated 0.0) when there have been no inquiries
    at all yet -- a leakage rate is meaningless with zero conversations to
    measure it against.
    """
    total_inquiries_result = await session.execute(
        select(func.coalesce(func.sum(Listing.inquiry_count), 0))
    )
    total_inquiries = total_inquiries_result.scalar_one()
    if total_inquiries <= 0:
        return None

    total_transactions = (
        await session.execute(select(func.count()).select_from(Transaction))
    ).scalar_one()

    # A listing can receive more than one Transaction attempt per inquiry
    # (retries after a failed/expired hold, FEAT-013 AC), so this ratio is
    # clamped at 1.0 converted (0.0 leakage) rather than going negative --
    # it is a monitoring signal, not a strict per-conversation join.
    converted_rate = min(total_transactions / total_inquiries, 1.0)
    return round(1.0 - converted_rate, 4)


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
        "leakage_rate": await leakage_rate(session),
    }
