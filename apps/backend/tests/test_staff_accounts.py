"""Tests for FEAT-033 Admin Staff Account Management.

Runs against an in-memory SQLite database (via aiosqlite) rather than a
live Postgres instance -- only the `users` and `audit_log_entries` tables
are created (not the full SQLModel.metadata, since other models use
Postgres-only column types like GeoAlchemy2 Geography that SQLite can't
compile), which is sufficient for exercising this feature's logic.
"""

import uuid
from collections.abc import AsyncIterator

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.db import get_session
from app.core.security import UserRole, create_access_token, hash_password
from app.main import app
from app.models.ops import AuditLogEntry
from app.models.user import User

pytestmark = pytest.mark.asyncio


@pytest_asyncio.fixture
async def session() -> AsyncIterator[AsyncSession]:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(
            User.metadata.create_all, tables=[User.__table__, AuditLogEntry.__table__]
        )

    factory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    async with factory() as sess:
        yield sess
    await engine.dispose()


async def _make_user(session: AsyncSession, *, role: str, is_active: bool = True) -> User:
    user = User(
        full_name=f"Test {role}",
        email=f"{role}-{uuid.uuid4()}@example.com",
        role=role,
        is_active=is_active,
        password_hash=hash_password("irrelevant-password-123"),
    )
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return user


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


# -- "always at least one active Admin" invariant --------------------------


async def test_cannot_deactivate_the_last_active_admin(
    client: AsyncClient, session: AsyncSession
) -> None:
    admin = await _make_user(session, role=UserRole.DEDUKE_ADMIN.value)

    response = await client.post(
        f"/v1/staff-accounts/{admin.id}/deactivate", headers=_auth_header(admin)
    )

    assert response.status_code == 400
    assert "last active Admin" in response.json()["detail"]

    await session.refresh(admin)
    assert admin.is_active is True


async def test_cannot_demote_the_last_active_admin(
    client: AsyncClient, session: AsyncSession
) -> None:
    admin = await _make_user(session, role=UserRole.DEDUKE_ADMIN.value)

    response = await client.post(
        f"/v1/staff-accounts/{admin.id}/demote", headers=_auth_header(admin)
    )

    assert response.status_code == 400
    assert "last active Admin" in response.json()["detail"]

    await session.refresh(admin)
    assert admin.role == UserRole.DEDUKE_ADMIN.value


async def test_can_deactivate_admin_when_another_active_admin_remains(
    client: AsyncClient, session: AsyncSession
) -> None:
    acting_admin = await _make_user(session, role=UserRole.DEDUKE_ADMIN.value)
    other_admin = await _make_user(session, role=UserRole.DEDUKE_ADMIN.value)

    response = await client.post(
        f"/v1/staff-accounts/{other_admin.id}/deactivate", headers=_auth_header(acting_admin)
    )

    assert response.status_code == 200
    await session.refresh(other_admin)
    assert other_admin.is_active is False


# -- 403 for Staff attempting Admin-only actions ----------------------------


async def test_staff_cannot_list_staff_accounts(client: AsyncClient, session: AsyncSession) -> None:
    staff = await _make_user(session, role=UserRole.DEDUKE_STAFF.value)

    response = await client.get("/v1/staff-accounts", headers=_auth_header(staff))

    assert response.status_code == 403
    assert response.json()["detail"] == "You don't have permission to do this."


async def test_staff_cannot_invite(client: AsyncClient, session: AsyncSession) -> None:
    staff = await _make_user(session, role=UserRole.DEDUKE_STAFF.value)

    response = await client.post(
        "/v1/staff-accounts/invite",
        headers=_auth_header(staff),
        json={"full_name": "New Person", "email": "new.person@example.com"},
    )

    assert response.status_code == 403


async def test_staff_cannot_promote_or_demote(client: AsyncClient, session: AsyncSession) -> None:
    staff = await _make_user(session, role=UserRole.DEDUKE_STAFF.value)
    other_staff = await _make_user(session, role=UserRole.DEDUKE_STAFF.value)

    promote_response = await client.post(
        f"/v1/staff-accounts/{other_staff.id}/promote", headers=_auth_header(staff)
    )
    assert promote_response.status_code == 403

    deactivate_response = await client.post(
        f"/v1/staff-accounts/{other_staff.id}/deactivate", headers=_auth_header(staff)
    )
    assert deactivate_response.status_code == 403


# -- audit log entries written for each action ------------------------------


async def test_invite_writes_audit_log_entry(client: AsyncClient, session: AsyncSession) -> None:
    admin = await _make_user(session, role=UserRole.DEDUKE_ADMIN.value)

    response = await client.post(
        "/v1/staff-accounts/invite",
        headers=_auth_header(admin),
        json={"full_name": "New Person", "email": "new.person@example.com"},
    )

    assert response.status_code == 201
    new_user_id = response.json()["account"]["id"]
    assert "invite_link" in response.json()

    from sqlalchemy import select

    entries = (
        (
            await session.execute(
                select(AuditLogEntry).where(
                    AuditLogEntry.action_type == "staff_invited",
                    AuditLogEntry.target_id == new_user_id,
                )
            )
        )
        .scalars()
        .all()
    )
    assert len(entries) == 1
    assert entries[0].actor_id == admin.id
    assert entries[0].target_type == "User"


async def test_promote_demote_deactivate_reactivate_all_write_audit_log(
    client: AsyncClient, session: AsyncSession
) -> None:
    admin = await _make_user(session, role=UserRole.DEDUKE_ADMIN.value)
    staff = await _make_user(session, role=UserRole.DEDUKE_STAFF.value)

    promote = await client.post(
        f"/v1/staff-accounts/{staff.id}/promote", headers=_auth_header(admin)
    )
    assert promote.status_code == 200

    demote = await client.post(f"/v1/staff-accounts/{staff.id}/demote", headers=_auth_header(admin))
    assert demote.status_code == 200

    deactivate = await client.post(
        f"/v1/staff-accounts/{staff.id}/deactivate", headers=_auth_header(admin)
    )
    assert deactivate.status_code == 200

    reactivate = await client.post(
        f"/v1/staff-accounts/{staff.id}/reactivate", headers=_auth_header(admin)
    )
    assert reactivate.status_code == 200

    from sqlalchemy import select

    action_types = {
        row[0]
        for row in (
            await session.execute(
                select(AuditLogEntry.action_type).where(AuditLogEntry.target_id == staff.id)
            )
        ).all()
    }
    assert {
        "staff_promoted_to_admin",
        "admin_demoted_to_staff",
        "staff_deactivated",
        "staff_reactivated",
    } <= action_types
