"""Tests for FEAT-001 (Google & Firebase Sign-Up / Login) and the
Staff/Admin-only backend-managed password flow (FEAT-033) it left in
place. Firebase Admin SDK calls are mocked throughout (see
tests.conftest.mock_firebase_verify) -- these tests never require a real
Firebase project or credentials, matching test_chat.py's own pattern for
the other Firebase Admin SDK consumer in this codebase.
"""

from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import cache
from app.core.security import UserRole, hash_password
from app.models.user import User
from tests.conftest import mock_firebase_verify


def _firebase_signin(
    client: TestClient, *, uid: str, email: str | None = None, phone_number: str | None = None
):
    with mock_firebase_verify(uid=uid, email=email, phone_number=phone_number, name="Amaka Okafor"):
        return client.post("/v1/auth/firebase-exchange", json={"id_token": "fake-token"})


async def _create_staff_user(
    session: AsyncSession, *, email: str, password: str, role: UserRole = UserRole.DEDUKE_STAFF
) -> User:
    user = User(
        full_name="Staff Member",
        email=email,
        role=role.value,
        auth_provider="password",
        password_hash=hash_password(password),
        is_active=True,
    )
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return user


def test_firebase_exchange_creates_new_user_on_first_sign_in(client: TestClient) -> None:
    """AC: a first-time sign-in via any of the three methods creates a new
    User record and routes to Role Selection (checked here via
    `role == "seeker"`, the default a brand-new consumer account gets, and
    `is_new_user`, the field the client actually branches routing on)."""
    response = _firebase_signin(client, uid="uid-amaka", email="amaka@example.com")
    assert response.status_code == 200
    body = response.json()
    assert body["access_token"]
    assert body["refresh_token"]
    assert body["role"] == "seeker"
    assert body["is_new_user"] is True


def test_firebase_exchange_returning_identity_resolves_same_user(client: TestClient) -> None:
    """AC: a returning identity (matched by firebase_uid) routes to Home
    Feed/dashboard -- checked here via the same user_id being resolved
    across two separate sign-ins for the same Firebase uid, and
    `is_new_user` correctly flipping to False on the second."""
    first = _firebase_signin(client, uid="uid-returning", email="returning@example.com")
    second = _firebase_signin(client, uid="uid-returning", email="returning@example.com")
    assert first.json()["user_id"] == second.json()["user_id"]
    assert first.json()["is_new_user"] is True
    assert second.json()["is_new_user"] is False


def test_firebase_exchange_supports_phone_identity(client: TestClient) -> None:
    """AC: User can sign in/register with Firebase phone/OTP -- the ID
    token carries a phone_number claim instead of/alongside email."""
    response = _firebase_signin(client, uid="uid-phone", phone_number="+2348012345678")
    assert response.status_code == 200
    assert response.json()["role"] == "seeker"


def test_firebase_exchange_rejects_invalid_token(client: TestClient) -> None:
    """AC: provider-specific failures show a clear, specific error message
    rather than a generic 'something went wrong'."""
    with (
        patch("app.services.auth_service._is_configured", return_value=True),
        patch("app.services.auth_service._get_firebase_app", return_value=object()),
        patch("firebase_admin.auth.verify_id_token", side_effect=ValueError("bad token")),
    ):
        response = client.post("/v1/auth/firebase-exchange", json={"id_token": "garbage"})
    assert response.status_code == 401
    assert "verified" in response.json()["detail"].lower()


async def test_firebase_exchange_raises_when_unconfigured(session: AsyncSession) -> None:
    """firebase_service_account_json/firestore_project_id are REPLACE_ME in
    every deployed test/CI environment -- the service must fail loudly,
    not silently no-op. `_is_configured` is force-patched to False rather
    than trusting ambient .env state, matching test_chat.py's identical
    test for chat_service (tested at the service layer, not via the HTTP
    client, since an unhandled 5xx here isn't caught by any exception
    handler in app/main.py and would otherwise propagate through
    TestClient instead of becoming a clean response to assert on)."""
    from app.services import auth_service

    with (
        patch.object(auth_service, "_is_configured", return_value=False),
        pytest.raises(auth_service.FirebaseAuthUnavailableError),
    ):
        await auth_service.exchange_firebase_token(session, id_token="x")


async def test_firebase_exchange_rejects_email_collision_with_password_account(
    client: TestClient, session: AsyncSession
) -> None:
    """A first-time Firebase sign-in must not silently collide with an
    existing auth_provider="password" row sharing the same email (e.g. an
    Agency-invited team member, or Staff/Admin) -- User.email is unique,
    so without this guard the INSERT would raise an unhandled
    IntegrityError (500) instead of a clean, specific error."""
    await _create_staff_user(session, email="shared@example.com", password="supersecret1")

    response = _firebase_signin(client, uid="uid-new-firebase-identity", email="shared@example.com")

    assert response.status_code == 409
    assert "already exists" in response.json()["detail"].lower()


async def test_firebase_exchange_rejects_phone_collision_with_password_account(
    client: TestClient, session: AsyncSession
) -> None:
    """Same guard, for phone_number -- also unique on User."""
    user = User(
        full_name="Agency Team Member",
        email="teammate@agency.example.com",
        phone_number="+2348099999999",
        role="agency",
        auth_provider="password",
        password_hash=hash_password("invite-token-hash"),
        is_active=True,
    )
    session.add(user)
    await session.commit()

    response = _firebase_signin(
        client, uid="uid-new-phone-identity", phone_number="+2348099999999"
    )

    assert response.status_code == 409


async def test_firebase_exchange_deactivated_account_blocked(
    client: TestClient, session: AsyncSession
) -> None:
    """AC-adjacent (screens.md Screen 1 'Account Deactivated' state):
    Firebase verification succeeding does not bypass is_active."""
    user = User(
        full_name="Deactivated User",
        email="deactivated@example.com",
        role="seeker",
        auth_provider="firebase",
        firebase_uid="uid-deactivated",
        is_active=False,
    )
    session.add(user)
    await session.commit()

    response = _firebase_signin(client, uid="uid-deactivated", email="deactivated@example.com")
    assert response.status_code == 403


async def test_login_staff_with_email_and_password(
    client: TestClient, session: AsyncSession
) -> None:
    """FEAT-033: Admin Web Console login is unaffected by FEAT-001 --
    Staff/Admin still authenticate with a backend-managed password, never
    Firebase/Google."""
    await _create_staff_user(session, email="staff@example.com", password="supersecret1")

    response = client.post(
        "/v1/auth/login", json={"email": "staff@example.com", "password": "supersecret1"}
    )
    assert response.status_code == 200
    assert response.json()["role"] == "deduke_staff"


async def test_login_invalid_credentials_shows_specific_error(
    client: TestClient, session: AsyncSession
) -> None:
    """AC: Invalid credentials show a clear, specific error message."""
    await _create_staff_user(session, email="david@example.com", password="supersecret1")

    response = client.post(
        "/v1/auth/login", json={"email": "david@example.com", "password": "wrongpassword"}
    )
    assert response.status_code == 401
    assert "couldn't verify" in response.json()["detail"].lower()


def test_login_rejects_firebase_provider_account(client: TestClient) -> None:
    """A consumer (Firebase-provider) account has no password_hash --
    posting its email to the Staff/Admin /login endpoint must fail like
    any other invalid credential, not leak that the account exists via a
    different error."""
    _firebase_signin(client, uid="uid-consumer-only", email="consumer@example.com")
    response = client.post(
        "/v1/auth/login", json={"email": "consumer@example.com", "password": "whatever123"}
    )
    assert response.status_code == 401


def test_me_returns_current_user_identity(client: TestClient) -> None:
    """GET /v1/auth/me resolves the caller's identity from their token --
    used by the Admin Web Console's session layer."""
    signin = _firebase_signin(client, uid="uid-me-check", email="me-check@example.com")
    token = signin.json()["access_token"]

    response = client.get("/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    body = response.json()
    assert body["email"] == "me-check@example.com"
    assert body["role"] == "seeker"
    assert body["is_active"] is True


def test_me_requires_authentication(client: TestClient) -> None:
    response = client.get("/v1/auth/me")
    assert response.status_code in (401, 403)  # HTTPBearer rejects missing credentials


def test_login_and_session_persists_via_refresh(client: TestClient) -> None:
    """AC: User stays logged in across app restarts (refresh token) --
    exercised here via a Firebase sign-in, since that's FEAT-001's actual
    entry point now; FEAT-033's password login shares the same
    issue_tokens()/refresh_session() plumbing, covered separately above."""
    signin = _firebase_signin(client, uid="uid-ngozi", email="ngozi@example.com")
    assert signin.status_code == 200
    refresh_token = signin.json()["refresh_token"]

    refresh_response = client.post("/v1/auth/refresh", json={"refresh_token": refresh_token})
    assert refresh_response.status_code == 200
    assert refresh_response.json()["user_id"] == signin.json()["user_id"]


async def test_forgot_password_and_reset(client: TestClient, session: AsyncSession) -> None:
    """AC (FEAT-033): Staff/Admin can reset a forgotten backend-managed
    password."""
    await _create_staff_user(session, email="reset@example.com", password="oldpassword1")

    forgot_response = client.post("/v1/auth/forgot-password", json={"email": "reset@example.com"})
    assert forgot_response.status_code == 202

    keys = await cache.get_redis_client().keys("auth:pwreset:*")
    token = keys[0].split("auth:pwreset:")[1]

    reset_response = client.post(
        "/v1/auth/reset-password", json={"reset_token": token, "new_password": "newpassword1"}
    )
    assert reset_response.status_code == 204

    login_response = client.post(
        "/v1/auth/login", json={"email": "reset@example.com", "password": "newpassword1"}
    )
    assert login_response.status_code == 200


def test_forgot_password_unknown_email_does_not_leak_existence(client: TestClient) -> None:
    response = client.post("/v1/auth/forgot-password", json={"email": "doesnotexist@example.com"})
    assert response.status_code == 202


async def test_forgot_password_firebase_provider_account_is_a_no_op(
    client: TestClient,
) -> None:
    """A consumer (Firebase-provider) account's email must not trigger a
    De-Duke-hosted reset email -- FEAT-001's rewrite: password reset for
    those accounts is Firebase's own flow entirely. Asserted indirectly:
    no reset token ends up in the Cache for this email."""
    _firebase_signin(client, uid="uid-fb-reset", email="fb-reset@example.com")
    response = client.post("/v1/auth/forgot-password", json={"email": "fb-reset@example.com"})
    assert response.status_code == 202

    keys = await cache.get_redis_client().keys("auth:pwreset:*")
    assert keys == []


def test_get_notification_preferences_defaults_all_enabled(client: TestClient) -> None:
    """FEAT-024 AC: manage email notification preferences per category."""
    signin = _firebase_signin(client, uid="uid-prefs", email="prefs@example.com")
    token = signin.json()["access_token"]

    response = client.get(
        "/v1/auth/me/notification-preferences", headers={"Authorization": f"Bearer {token}"}
    )
    assert response.status_code == 200
    assert response.json()["email_notification_preferences"] == {
        "account": True,
        "verification": True,
        "payments": True,
    }


def test_update_notification_preferences_partial_update(client: TestClient) -> None:
    signin = _firebase_signin(client, uid="uid-prefs2", email="prefs2@example.com")
    token = signin.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    response = client.patch(
        "/v1/auth/me/notification-preferences", json={"payments": False}, headers=headers
    )
    assert response.status_code == 200
    body = response.json()["email_notification_preferences"]
    assert body["payments"] is False
    # Omitted categories are left unchanged, not reset.
    assert body["account"] is True
    assert body["verification"] is True

    # Confirm the partial update persisted, and a second unrelated toggle
    # doesn't clobber the first.
    second_response = client.patch(
        "/v1/auth/me/notification-preferences", json={"account": False}, headers=headers
    )
    second_body = second_response.json()["email_notification_preferences"]
    assert second_body["account"] is False
    assert second_body["payments"] is False


def test_notification_preferences_requires_authentication(client: TestClient) -> None:
    response = client.get("/v1/auth/me/notification-preferences")
    assert response.status_code in (401, 403)
