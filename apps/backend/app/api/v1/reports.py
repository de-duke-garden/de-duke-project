"""In-App Reporting endpoints -- FEAT-009.

POST /listings/{listing_id}/report and POST /conversations/{conversation_id}/report
are mobile-facing (any authenticated user reporting a listing or a chat
conversation, per screens.md Screen 6's Report IconButton spec). Every
`/admin/reports*` endpoint requires DEDUKE_STAFF or DEDUKE_ADMIN, enforced
server-side via `require_roles` (never hidden via client UI alone), and
surfaces into the same Admin Moderation Queue as moderation.py's
GET /moderation/queue (FEAT-025 AC).
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.security import CurrentUser, UserRole, get_current_user, require_roles
from app.models.report import Report
from app.schemas.report import (
    ReportCreateRequest,
    ReportListItem,
    ReportListResponse,
    ReportOut,
    ReportResolveRequest,
)
from app.services import report_service

# Three separate routers, since this module's endpoints mount under three
# different path prefixes in app/api/v1/__init__.py:
#   listing_report_router     -> included at prefix "/listings" (alongside
#                                 listings.router, same prefix, additive)
#   conversation_report_router -> included at prefix "/conversations"
#   router (admin)             -> included at prefix "/admin/reports"
listing_report_router = APIRouter()
conversation_report_router = APIRouter()
router = APIRouter()

staff_or_admin = require_roles(UserRole.DEDUKE_STAFF, UserRole.DEDUKE_ADMIN)


def _to_out(report: Report) -> ReportOut:
    return ReportOut(
        id=report.id,
        target_type=report.target_type,
        target_id=report.target_id,
        reason=report.reason,
        status=report.status,
        created_at=report.created_at,
    )


async def _create(
    session: AsyncSession,
    *,
    target_type: str,
    target_id: str,
    payload: ReportCreateRequest,
    current_user: CurrentUser,
) -> ReportOut:
    try:
        report = await report_service.create_report(
            session,
            reporter_user_id=current_user.user_id,
            target_type=target_type,
            target_id=target_id,
            reason=payload.reason,
            detail=payload.detail,
        )
    except report_service.ReportError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return _to_out(report)


# Mounted at prefix "/listings" (see app/api/v1/__init__.py) so the public
# route is POST /v1/listings/{listing_id}/report, per screens.md Screen 6.
@listing_report_router.post(
    "/{listing_id}/report", response_model=ReportOut, status_code=status.HTTP_201_CREATED
)
async def report_listing(
    listing_id: str,
    payload: ReportCreateRequest,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> ReportOut:
    return await _create(
        session,
        target_type="listing",
        target_id=listing_id,
        payload=payload,
        current_user=current_user,
    )


# Mounted at prefix "/conversations" so the public route is
# POST /v1/conversations/{conversation_id}/report, matching chat_service's
# Firestore conversation ids (never a Primary-DB FK -- see report.py).
@conversation_report_router.post(
    "/{conversation_id}/report", response_model=ReportOut, status_code=status.HTTP_201_CREATED
)
async def report_conversation(
    conversation_id: str,
    payload: ReportCreateRequest,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> ReportOut:
    return await _create(
        session,
        target_type="conversation",
        target_id=conversation_id,
        payload=payload,
        current_user=current_user,
    )


# Mounted at prefix "/admin/reports".
@router.get("", response_model=ReportListResponse)
async def list_reports(
    status_filter: str | None = None,
    cursor: str | None = None,
    limit: int = 20,
    _current_user: CurrentUser = Depends(staff_or_admin),
    session: AsyncSession = Depends(get_session),
) -> ReportListResponse:
    try:
        rows, next_cursor = await report_service.list_reports(
            session, status_filter=status_filter, cursor=cursor, limit=limit
        )
    except report_service.ReportError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    items = [
        ReportListItem(
            id=r.id,
            reporter_user_id=r.reporter_user_id,
            reporter_name=await report_service.get_user_name_or_unknown(
                session, r.reporter_user_id
            ),
            target_type=r.target_type,
            target_id=r.target_id,
            reason=r.reason,
            detail=r.detail,
            status=r.status,
            created_at=r.created_at,
            resolved_at=r.resolved_at,
            resolution_note=r.resolution_note,
        )
        for r in rows
    ]
    return ReportListResponse(items=items, next_cursor=next_cursor)


async def _get_report_or_404(session: AsyncSession, report_id: str) -> Report:
    report = await report_service.get_report(session, report_id)
    if report is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Report not found.")
    return report


@router.post("/{report_id}/resolve", response_model=ReportOut)
async def resolve_report(
    report_id: str,
    payload: ReportResolveRequest,
    current_user: CurrentUser = Depends(staff_or_admin),
    session: AsyncSession = Depends(get_session),
) -> ReportOut:
    report = await _get_report_or_404(session, report_id)
    try:
        report = await report_service.resolve_report(
            session,
            report=report,
            resolution_note=payload.resolution_note,
            actor_id=current_user.user_id,
        )
    except report_service.ReportError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return _to_out(report)


@router.post("/{report_id}/dismiss", response_model=ReportOut)
async def dismiss_report(
    report_id: str,
    payload: ReportResolveRequest,
    current_user: CurrentUser = Depends(staff_or_admin),
    session: AsyncSession = Depends(get_session),
) -> ReportOut:
    report = await _get_report_or_404(session, report_id)
    try:
        report = await report_service.dismiss_report(
            session,
            report=report,
            resolution_note=payload.resolution_note,
            actor_id=current_user.user_id,
        )
    except report_service.ReportError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return _to_out(report)
