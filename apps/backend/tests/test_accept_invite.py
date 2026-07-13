"""Tests for the missing half of FEAT-033's invite AC ("the invitee sets
their own password via an emailed invitation link") -- POST
/v1/auth/accept-invite (app/services/auth_service.py::accept_invite).

Exercises the real FEAT-033 staff-invite flow end to end: invite a Staff
member, extract the token from the invite_link the invite endpoint
returns, then accept it.
"""

import uuid
from collections.abc import AsyncIterator
from urllib.parse import parse_qs, urlparse

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


async def _make_admin(session: AsyncSession) -> User:
    user = User(
        full_name="Test Admin",
        email=f"admin-{uuid.uuid4()}@example.com",
        role=UserRole.DEDUKE_ADMIN.value,
        is_active=True,
        password_hash=hash_password("irrelevant-password-123"),
    )
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return user


def _auth_header(user: User) -> dict[str, str]:
    token = create_access_token(user_id=user.id, role=UserRole(user.role))
    return {"Authorization": f"Bearer {token}"}


@pytest_asyncio.fixture
async def client(session: AsyncSession) -> AsyncIterator[AsyncClient]:
    async def override_get_session() -> AsyncIterator[AsyncSession]:
        yield session

    app.dependency_overrides[get_session] = override_get_session
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()


def _extract_uid_and_token(invite_link: str) -> tuple[str, str]:
    query = parse_qs(urlparse(invite_link).query)
    return query["uid"][0], query["token"][0]


async def _invite_staff(client: AsyncClient, admin: User) -> tuple[str, str]:
    response = await client.post(
        "/v1/staff-accounts/invite",
        headers=_auth_header(admin),
        json={"full_name": "New Staffer", "email": f"staffer-{uuid.uuid4()}@example.com"},
    )
    assert response.status_code == 201
    invite_link = response.json()["invite_link"]
    return _extract_uid_and_token(invite_link)


async def test_accept_invite_sets_password_and_returns_session(
    client: AsyncClient, session: AsyncSession
) -> None:
    admin = await _make_admin(session)
    uid, token = await _invite_staff(client, admin)

    response = await client.post(
        "/v1/auth/accept-invite",
        json={"user_id": uid, "invite_token": token, "new_password": "aRealChosenPassword1"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["access_token"]
    assert body["refresh_token"]
    assert body["role"] == "deduke_staff"

    # The invitee can now log in with their newly chosen password.
    login = await client.post(
        "/v1/auth/login",
        json={
            "email": (await session.get(User, uid)).email,
            "password": "aRealChosenPassword1",
        },
    )
    assert login.status_code == 200


async def test_accept_invite_rejects_wrong_token(
    client: AsyncClient, session: AsyncSession
) -> None:
    admin = await _make_admin(session)
    uid, _correct_token = await _invite_staff(client, admin)

    response = await client.post(
        "/v1/auth/accept-invite",
        json={"user_id": uid, "invite_token": "totally-wrong-token", "new_password": "x1234567"},
    )

    assert response.status_code == 400
    assert "invalid" in response.json()["detail"].lower()


async def test_accept_invite_token_is_single_use(
    client: AsyncClient, session: AsyncSession
) -> None:
    """Replaying the same invite link a second time must fail -- the first
    accept already overwrote password_hash, so the original token no
    longer verifies against it."""
    admin = await _make_admin(session)
    uid, token = await _invite_staff(client, admin)

    first = await client.post(
        "/v1/auth/accept-invite",
        json={"user_id": uid, "invite_token": token, "new_password": "firstChoicePassword1"},
    )
    assert first.status_code == 200

    second = await client.post(
        "/v1/auth/accept-invite",
        json={"user_id": uid, "invite_token": token, "new_password": "secondAttemptPassword1"},
    )
    assert second.status_code == 400


async def test_accept_invite_rejects_deactivated_account(
    client: AsyncClient, session: AsyncSession
) -> None:
    admin = await _make_admin(session)
    uid, token = await _invite_staff(client, admin)

    deactivate = await client.post(
        f"/v1/staff-accounts/{uid}/deactivate", headers=_auth_header(admin)
    )
    assert deactivate.status_code == 200

    response = await client.post(
        "/v1/auth/accept-invite",
        json={"user_id": uid, "invite_token": token, "new_password": "someRealPassword1"},
    )
    assert response.status_code == 403


async def test_accept_invite_rejects_unknown_user_id(client: AsyncClient) -> None:
    response = await client.post(
        "/v1/auth/accept-invite",
        json={
            "user_id": "does-not-exist",
            "invite_token": "whatever",
            "new_password": "someRealPassword1",
        },
    )
    assert response.status_code == 400
