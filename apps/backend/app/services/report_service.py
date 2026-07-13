"""In-App Reporting business logic -- FEAT-009.

Seekers report a listing or a chat conversation from the mobile app
(POST /v1/listings/{id}/report, POST /v1/conversations/{id}/report);
Staff/Admin review, resolve, or dismiss reports via the Admin Web
Console's Moderation Queue (GET /v1/admin/reports, same queue
moderation_service.list_moderation_queue feeds, distinguished there via
the `queue_item_type` discriminator per FEAT-025 AC).
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.listing import Listing
from app.models.ops import AuditLogEntry
from app.models.report import REPORT_REASONS, REPORT_STATUSES, Report
from app.models.user import User

RESOLVABLE_STATUSES = ("resolved", "dismissed")


class ReportError(Exception):
    """Raised for any report-service-level validation failure. Callers
    (app/api/v1/reports.py) map this to HTTP 400/404 as appropriate --
    never to a 500, mirroring dispute_service.DisputeError."""


async def create_report(
    session: AsyncSession,
    *,
    reporter_user_id: str,
    target_type: str,
    target_id: str,
    reason: str,
    detail: str | None,
) -> Report:
    if target_type not in ("listing", "conversation"):
        raise ReportError("target_type must be 'listing' or 'conversation'.")
    if reason not in REPORT_REASONS:
        raise ReportError(f"reason must be one of {REPORT_REASONS}")

    if target_type == "listing":
        listing = (
            await session.execute(select(Listing).where(Listing.id == target_id))
        ).scalar_one_or_none()
        if listing is None:
            raise ReportError("Listing not found.")

    report = Report(
        reporter_user_id=reporter_user_id,
        target_type=target_type,
        target_id=target_id,
        reason=reason,
        detail=detail,
    )
    session.add(report)
    session.add(
        AuditLogEntry(
            actor_id=reporter_user_id,
            action_type="report_submitted",
            target_type="Report",
            target_id=report.id,
            notes=f"target_type={target_type} target_id={target_id} reason={reason}",
        )
    )
    await session.commit()
    await session.refresh(report)

    from app.services import analytics_service

    await analytics_service.track_event(
        event_name=analytics_service.REPORT_SUBMITTED,
        user_id=reporter_user_id,
        properties={"target_type": target_type, "target_id": target_id, "reason": reason},
    )

    return report


async def list_reports(
    session: AsyncSession,
    *,
    status_filter: str | None = None,
    cursor: str | None = None,
    limit: int = 20,
) -> tuple[list[Report], str | None]:
    """Cursor-based (keyset) pagination on `id`, per AGENTS.md -- never
    offset/page-number pagination. Mirrors transactions.py's list pattern."""
    limit = max(1, min(limit, 100))
    query = select(Report).order_by(Report.id).limit(limit + 1)
    if status_filter:
        if status_filter not in REPORT_STATUSES:
            raise ReportError(f"status must be one of {REPORT_STATUSES}")
        query = query.where(Report.status == status_filter)
    if cursor:
        query = query.where(Report.id > cursor)

    result = await session.execute(query)
    rows = list(result.scalars().all())
    has_more = len(rows) > limit
    rows = rows[:limit]
    # Cursor is the last item actually returned on this page (not the
    # peeked limit+1-th row) so the next page's `id > cursor` filter
    # picks back up exactly where this page left off, per AGENTS.md
    # cursor/keyset pagination -- never offset/page-number.
    next_cursor = rows[-1].id if has_more and rows else None
    return rows, next_cursor


async def get_report(session: AsyncSession, report_id: str) -> Report | None:
    return (
        await session.execute(select(Report).where(Report.id == report_id))
    ).scalar_one_or_none()


async def get_user_name_or_unknown(session: AsyncSession, user_id: str | None) -> str:
    if user_id is None:
        return "Unknown"
    user = await session.get(User, user_id)
    return user.full_name if user is not None else "Unknown"


async def _resolve(
    session: AsyncSession,
    *,
    report: Report,
    new_status: str,
    resolution_note: str,
    actor_id: str,
    action_type: str,
) -> Report:
    if report.status in RESOLVABLE_STATUSES:
        raise ReportError("This report has already been resolved.")

    report.status = new_status
    report.resolution_note = resolution_note
    report.resolved_at = datetime.now(UTC)
    report.resolved_by_user_id = actor_id
    session.add(report)
    session.add(
        AuditLogEntry(
            actor_id=actor_id,
            action_type=action_type,
            target_type="Report",
            target_id=report.id,
            notes=resolution_note,
        )
    )
    await session.commit()
    await session.refresh(report)
    return report


async def resolve_report(
    session: AsyncSession, *, report: Report, resolution_note: str, actor_id: str
) -> Report:
    return await _resolve(
        session,
        report=report,
        new_status="resolved",
        resolution_note=resolution_note,
        actor_id=actor_id,
        action_type="report_resolved",
    )


async def dismiss_report(
    session: AsyncSession, *, report: Report, resolution_note: str, actor_id: str
) -> Report:
    return await _resolve(
        session,
        report=report,
        new_status="dismissed",
        resolution_note=resolution_note,
        actor_id=actor_id,
        action_type="report_dismissed",
    )


async def list_open_reports_for_queue(session: AsyncSession) -> list[Report]:
    """Feeds moderation_service.list_moderation_queue's merged view --
    only 'open'/'reviewing' reports belong in the active queue, newest
    first (same recency ordering as list_moderation_queue's listings)."""
    stmt = (
        select(Report)
        .where(Report.status.in_(("open", "reviewing")))
        .order_by(Report.created_at.asc())
    )
    result = await session.execute(stmt)
    return list(result.scalars().all())
