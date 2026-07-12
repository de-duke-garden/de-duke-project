"""Operations metrics -- FEAT-034 (Operations Analytics Dashboard).

architecture.md's Product Analytics Pipeline component specifies that
dashboard reads always go against a periodically-refreshed aggregate
store, never live queries against the transactional Primary Database, so
viewing a dashboard never competes with production traffic. This module
is a pragmatic MVP that computes the same metrics via direct SQL
aggregate queries against the Primary Database instead -- there is no
separately-provisioned Product Analytics Platform yet (analytics_service.py
is still a no-op stub, same REPLACE_ME-gated pattern as every other
unconfigured third-party dependency in this codebase), so there is nothing
to materialize a periodically-refreshed store FROM yet.

TODO(analytics): once analytics_service.py has a real platform wired up
and event volume justifies it, replace these functions' bodies with reads
against that platform's aggregate/materialized-view store instead of
querying Listing/HostAccount/Dispute/Transaction directly. Until then,
these are read-only aggregate queries (COUNT/AVG, no row-level scans of
sensitive data) -- acceptable load for this stage, not equivalent to the
transactional writes (booking holds, payments) this note is protecting.

General Support Inbox metrics (screens.md Screen 29's "Support" card) are
NOT included here -- that data lives in Firestore
(support_conversations), which this module (Primary-Database-only) has no
access to. Computing them requires either a scheduled Firestore ->
Postgres ETL job or the real analytics pipeline ingesting support events
directly; neither exists yet, so `support_inbox` in the returned shape is
explicitly `None` rather than a fabricated number.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.host_account import HostAccount
from app.models.listing import Listing
from app.models.ops import Dispute
from app.models.transaction import Transaction
from app.services.moderation_service import MODERATABLE_STATUSES


def _as_aware(dt: datetime) -> datetime:
    """Normalizes to tz-aware UTC. Every datetime column this module reads
    is declared `sa_type=DateTime(timezone=True)` and Postgres/asyncpg
    always round-trips it tz-aware -- this guard only matters against
    SQLite (the test harness), which silently drops tzinfo on read even
    for a timezone-aware column."""
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=UTC)


async def moderation_queue_stats(session: AsyncSession) -> dict[str, Any]:
    """Current queue size + average age, overall and broken down by host
    type (screens.md Screen 29 AC) -- "age" is time since Listing.created_at
    for listings still in an un-reviewed status, there being no separate
    "entered queue at" timestamp distinct from creation in the current
    schema (a listing enters the queue at creation and leaves it at the
    moderation decision, per moderation_service.py)."""
    stmt = (
        select(Listing.created_at, HostAccount.host_type)
        .join(HostAccount, HostAccount.id == Listing.host_account_id)
        .where(Listing.status.in_(MODERATABLE_STATUSES))
    )
    rows = (await session.execute(stmt)).all()

    now = datetime.now(UTC)
    by_host_type: dict[str, dict[str, Any]] = {}
    total_age_hours = 0.0

    for created_at, host_type in rows:
        age_hours = (now - _as_aware(created_at)).total_seconds() / 3600
        total_age_hours += age_hours
        bucket = by_host_type.setdefault(host_type, {"count": 0, "total_age_hours": 0.0})
        bucket["count"] += 1
        bucket["total_age_hours"] += age_hours

    for bucket in by_host_type.values():
        bucket["avg_age_hours"] = (
            bucket.pop("total_age_hours") / bucket["count"] if bucket["count"] else 0.0
        )

    return {
        "queue_size": len(rows),
        "avg_age_hours": (total_age_hours / len(rows)) if rows else 0.0,
        "by_host_type": by_host_type,
    }


async def host_verification_stats(session: AsyncSession) -> dict[str, Any]:
    """Host Verification Review's own queue size/age/turnaround, broken
    down by host type (screens.md Screen 29 AC) -- separate from the
    listing moderation queue above, same "age since created_at" basis."""
    pending_stmt = select(HostAccount.created_at, HostAccount.host_type).where(
        HostAccount.status == "in_review"
    )
    pending_rows = (await session.execute(pending_stmt)).all()

    now = datetime.now(UTC)
    by_host_type: dict[str, dict[str, Any]] = {}
    total_age_hours = 0.0

    for created_at, host_type in pending_rows:
        age_hours = (now - _as_aware(created_at)).total_seconds() / 3600
        total_age_hours += age_hours
        bucket = by_host_type.setdefault(host_type, {"count": 0, "total_age_hours": 0.0})
        bucket["count"] += 1
        bucket["total_age_hours"] += age_hours

    for bucket in by_host_type.values():
        bucket["avg_age_hours"] = (
            bucket.pop("total_age_hours") / bucket["count"] if bucket["count"] else 0.0
        )

    return {
        "queue_size": len(pending_rows),
        "avg_age_hours": (total_age_hours / len(pending_rows)) if pending_rows else 0.0,
        "by_host_type": by_host_type,
    }


async def dispute_stats(session: AsyncSession) -> dict[str, Any]:
    """Dispute volume + average resolution time (screens.md Screen 29 AC).
    Report volume (FEAT-009, In-App Reporting) is Phase 3, not yet
    implemented -- this reports dispute volume only, not a combined
    report+dispute figure the AC's wording implies will exist once FEAT-009
    ships."""
    open_count = (
        await session.execute(
            select(func.count()).select_from(Dispute).where(Dispute.status.in_(("open", "under_review")))
        )
    ).scalar_one()

    resolved_stmt = select(Dispute.created_at, Dispute.resolved_at).where(
        Dispute.resolved_at.is_not(None)
    )
    resolved_rows = (await session.execute(resolved_stmt)).all()
    if resolved_rows:
        total_hours = sum(
            (resolved_at - created_at).total_seconds() / 3600
            for created_at, resolved_at in resolved_rows
        )
        avg_resolution_hours = total_hours / len(resolved_rows)
    else:
        avg_resolution_hours = 0.0

    return {
        "open_count": open_count,
        "resolved_count": len(resolved_rows),
        "avg_resolution_hours": avg_resolution_hours,
    }


async def booking_hold_stats(session: AsyncSession) -> dict[str, Any]:
    """Hold-to-payment conversion rate and hold-expiry rate (screens.md
    Screen 29 AC, FEAT-032) -- computed from the full lifetime distribution
    of Transaction.status for now (not yet date-range-scoped; see this
    module's header re: MVP status)."""
    stmt = select(Transaction.status, func.count()).group_by(Transaction.status)
    rows = dict((await session.execute(stmt)).all())

    total_holds = sum(rows.values())
    succeeded = rows.get("succeeded", 0)
    expired = rows.get("expired", 0)

    return {
        "total_holds": total_holds,
        "hold_to_payment_conversion_rate": (succeeded / total_holds) if total_holds else 0.0,
        "hold_expiry_rate": (expired / total_holds) if total_holds else 0.0,
        "by_status": rows,
    }


async def staff_workload(session: AsyncSession) -> dict[str, int]:
    """Open item counts per staff member (screens.md Screen 29 AC) --
    currently only Dispute carries a Primary-Database assignedStaffId
    column; ChatConversation.assignedStaffId lives in Firestore (out of
    reach here, same limitation as support_inbox_stats' absence -- see
    this module's header) and the listing moderation queue has no
    per-staff assignment concept at all in the current schema (reviewed
    by whichever staff member picks up the queue, not pre-assigned)."""
    stmt = (
        select(Dispute.assigned_staff_id, func.count())
        .where(Dispute.status.in_(("open", "under_review")), Dispute.assigned_staff_id.is_not(None))
        .group_by(Dispute.assigned_staff_id)
    )
    rows = (await session.execute(stmt)).all()
    return {staff_id: count for staff_id, count in rows}


async def get_operations_dashboard(session: AsyncSession) -> dict[str, Any]:
    return {
        "moderation_queue": await moderation_queue_stats(session),
        "host_verification": await host_verification_stats(session),
        "disputes": await dispute_stats(session),
        # Firestore-only data, genuinely unavailable from this module --
        # see header docstring. Never fabricated.
        "support_inbox": None,
        "booking_holds": await booking_hold_stats(session),
        "staff_workload": await staff_workload(session),
    }
