"""Tests for FEAT-009 In-App Reporting -- app/services/report_service.py
plus the role-gate and creation flow on app/api/v1/reports.py.

`Listing` has a PostGIS Geography column, which the SQLite test harness
excludes from table creation (see conftest.py's _sqlite_safe_tables) --
so listing-target report tests use a mocked session.execute the same way
tests/test_moderation_service.py stands in for Listing rows. Conversation-
target reports need no Listing lookup at all, so those run against a real
in-memory SQLite DB (User, Report, AuditLogEntry), mirroring
tests/test_dispute_service.py's pattern.
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncIterator
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.db import get_session
from app.core.security import UserRole, create_access_token, hash_password
from app.main import app
from app.models.ops import AuditLogEntry
from app.models.report import Report
from app.models.user import User
from app.services import report_service

pytestmark = pytest.mark.asyncio


@pytest_asyncio.fixture
async def session() -> AsyncIterator[AsyncSession]:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(
            User.metadata.create_all,
            tables=[User.__table__, Report.__table__, AuditLogEntry.__table__],
        )

    factory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    async with factory() as sess:
        yield sess
    await engine.dispose()


async def _make_user(session: AsyncSession, *, role: str) -> User:
    user = User(
        full_name=f"Test {role}",
        email=f"{role}-{uuid.uuid4()}@example.com",
        role=role,
        is_active=True,
        password_hash=hash_password("irrelevant-password-123"),
    )
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return user


@pytest_asyncio.fixture(autouse=True)
def _stub_analytics():
    with patch("app.services.analytics_service.track_event", new=AsyncMock()):
        yield


# -- create_report (conversation target -- no Listing lookup needed) --------


async def test_create_conversation_report_success(session: AsyncSession) -> None:
    guest = await _make_user(session, role="guest")

    report = await report_service.create_report(
        session,
        reporter_user_id=guest.id,
        target_type="conversation",
        target_id="conv-123",
        reason="scam",
        detail="Asked me to pay via bank transfer outside the app.",
    )

    assert report.status == "open"
    assert report.target_type == "conversation"
    assert report.target_id == "conv-123"
    assert report.reporter_user_id == guest.id


async def test_create_report_rejects_invalid_reason(session: AsyncSession) -> None:
    guest = await _make_user(session, role="guest")

    with pytest.raises(report_service.ReportError, match="reason must be one of"):
        await report_service.create_report(
            session,
            reporter_user_id=guest.id,
            target_type="conversation",
            target_id="conv-123",
            reason="not_a_real_reason",
            detail=None,
        )


async def test_create_report_rejects_invalid_target_type(session: AsyncSession) -> None:
    guest = await _make_user(session, role="guest")

    with pytest.raises(report_service.ReportError, match="target_type must be"):
        await report_service.create_report(
            session,
            reporter_user_id=guest.id,
            target_type="host",
            target_id="host-123",
            reason="other",
            detail=None,
        )


async def test_create_listing_report_rejects_unknown_listing() -> None:
    """Listing existence check uses a real select() against session.execute
    -- mocked here the same way test_moderation_service.py stands in for
    Listing (Geography column blocks SQLite table creation)."""
    session = MagicMock()
    execute_result = MagicMock()
    execute_result.scalar_one_or_none.return_value = None
    session.execute = AsyncMock(return_value=execute_result)

    with pytest.raises(report_service.ReportError, match="Listing not found"):
        await report_service.create_report(
            session,
            reporter_user_id="guest-1",
            target_type="listing",
            target_id="does-not-exist",
            reason="fake",
            detail=None,
        )


# -- list_reports (cursor pagination) ----------------------------------------


async def test_list_reports_cursor_pagination(session: AsyncSession) -> None:
    guest = await _make_user(session, role="guest")
    for i in range(3):
        await report_service.create_report(
            session,
            reporter_user_id=guest.id,
            target_type="conversation",
            target_id=f"conv-{i}",
            reason="other",
            detail=None,
        )

    page_one, cursor = await report_service.list_reports(session, limit=2)
    assert len(page_one) == 2
    assert cursor is not None

    page_two, cursor_two = await report_service.list_reports(session, cursor=cursor, limit=2)
    assert len(page_two) == 1
    assert cursor_two is None


async def test_list_reports_filters_by_status(session: AsyncSession) -> None:
    guest = await _make_user(session, role="guest")
    staff = await _make_user(session, role="deduke_staff")
    open_report = await report_service.create_report(
        session,
        reporter_user_id=guest.id,
        target_type="conversation",
        target_id="conv-open",
        reason="other",
        detail=None,
    )
    to_resolve = await report_service.create_report(
        session,
        reporter_user_id=guest.id,
        target_type="conversation",
        target_id="conv-resolved",
        reason="other",
        detail=None,
    )
    await report_service.resolve_report(
        session, report=to_resolve, resolution_note="Handled.", actor_id=staff.id
    )

    open_only, _ = await report_service.list_reports(session, status_filter="open")
    assert [r.id for r in open_only] == [open_report.id]

    resolved_only, _ = await report_service.list_reports(session, status_filter="resolved")
    assert [r.id for r in resolved_only] == [to_resolve.id]


# -- resolve_report / dismiss_report (writes AuditLogEntry) ------------------


async def test_resolve_report_writes_audit_log_entry(session: AsyncSession) -> None:
    from sqlalchemy import select

    guest = await _make_user(session, role="guest")
    staff = await _make_user(session, role="deduke_staff")
    report = await report_service.create_report(
        session,
        reporter_user_id=guest.id,
        target_type="conversation",
        target_id="conv-1",
        reason="scam",
        detail=None,
    )

    resolved = await report_service.resolve_report(
        session,
        report=report,
        resolution_note="Investigated, confirmed scam attempt.",
        actor_id=staff.id,
    )

    assert resolved.status == "resolved"
    assert resolved.resolved_at is not None
    assert resolved.resolved_by_user_id == staff.id

    audit_rows = (
        (await session.execute(select(AuditLogEntry).where(AuditLogEntry.target_id == report.id)))
        .scalars()
        .all()
    )
    action_types = {row.action_type for row in audit_rows}
    assert "report_submitted" in action_types
    assert "report_resolved" in action_types


async def test_dismiss_report_writes_audit_log_entry(session: AsyncSession) -> None:
    guest = await _make_user(session, role="guest")
    staff = await _make_user(session, role="deduke_staff")
    report = await report_service.create_report(
        session,
        reporter_user_id=guest.id,
        target_type="conversation",
        target_id="conv-1",
        reason="other",
        detail=None,
    )

    dismissed = await report_service.dismiss_report(
        session, report=report, resolution_note="Not actionable.", actor_id=staff.id
    )

    assert dismissed.status == "dismissed"
    assert dismissed.resolved_by_user_id == staff.id


async def test_resolve_already_resolved_report_raises(session: AsyncSession) -> None:
    guest = await _make_user(session, role="guest")
    staff = await _make_user(session, role="deduke_staff")
    report = await report_service.create_report(
        session,
        reporter_user_id=guest.id,
        target_type="conversation",
        target_id="conv-1",
        reason="other",
        detail=None,
    )
    await report_service.resolve_report(
        session, report=report, resolution_note="Handled.", actor_id=staff.id
    )

    with pytest.raises(report_service.ReportError, match="already been resolved"):
        await report_service.resolve_report(
            session, report=report, resolution_note="Again.", actor_id=staff.id
        )


# -- list_open_reports_for_queue (FEAT-025 discriminator source) ------------


async def test_list_open_reports_for_queue_excludes_resolved(session: AsyncSession) -> None:
    guest = await _make_user(session, role="guest")
    staff = await _make_user(session, role="deduke_staff")
    open_report = await report_service.create_report(
        session,
        reporter_user_id=guest.id,
        target_type="conversation",
        target_id="conv-open",
        reason="other",
        detail=None,
    )
    resolved_report = await report_service.create_report(
        session,
        reporter_user_id=guest.id,
        target_type="conversation",
        target_id="conv-resolved",
        reason="other",
        detail=None,
    )
    await report_service.resolve_report(
        session, report=resolved_report, resolution_note="Handled.", actor_id=staff.id
    )

    queue_reports = await report_service.list_open_reports_for_queue(session)
    assert [r.id for r in queue_reports] == [open_report.id]


# -- API-layer role gate + creation flow (mirrors test_dispute_service.py) ---


@pytest_asyncio.fixture
async def client(session: AsyncSession) -> AsyncIterator[AsyncClient]:
    async def override_get_session() -> AsyncIterator[AsyncSession]:
        yield session

    app.dependency_overrides[get_session] = override_get_session
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()


def _auth_header(user: User) -> dict[str, str]:
    token = create_access_token(user_id=user.id, role=UserRole(user.role))
    return {"Authorization": f"Bearer {token}"}


async def test_guest_can_report_conversation_via_api(
    client: AsyncClient, session: AsyncSession
) -> None:
    guest = await _make_user(session, role="guest")

    response = await client.post(
        "/v1/conversations/conv-abc/report",
        json={"reason": "scam", "detail": "Wanted cash outside the app."},
        headers=_auth_header(guest),
    )

    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "open"
    assert body["target_type"] == "conversation"
    assert body["target_id"] == "conv-abc"


async def test_guest_cannot_list_admin_reports(client: AsyncClient, session: AsyncSession) -> None:
    guest = await _make_user(session, role="guest")

    response = await client.get("/v1/admin/reports", headers=_auth_header(guest))

    assert response.status_code == 403


async def test_guest_cannot_resolve_reports(client: AsyncClient, session: AsyncSession) -> None:
    guest = await _make_user(session, role="guest")
    report = await report_service.create_report(
        session,
        reporter_user_id=guest.id,
        target_type="conversation",
        target_id="conv-1",
        reason="other",
        detail=None,
    )

    response = await client.post(
        f"/v1/admin/reports/{report.id}/resolve",
        json={"resolution_note": "n/a"},
        headers=_auth_header(guest),
    )

    assert response.status_code == 403


async def test_staff_can_list_and_resolve_reports_via_api(
    client: AsyncClient, session: AsyncSession
) -> None:
    guest = await _make_user(session, role="guest")
    staff = await _make_user(session, role="deduke_staff")
    report = await report_service.create_report(
        session,
        reporter_user_id=guest.id,
        target_type="conversation",
        target_id="conv-1",
        reason="scam",
        detail=None,
    )

    list_response = await client.get("/v1/admin/reports", headers=_auth_header(staff))
    assert list_response.status_code == 200
    assert len(list_response.json()["items"]) == 1

    resolve_response = await client.post(
        f"/v1/admin/reports/{report.id}/resolve",
        json={"resolution_note": "Reviewed, confirmed scam."},
        headers=_auth_header(staff),
    )
    assert resolve_response.status_code == 200
    assert resolve_response.json()["status"] == "resolved"
