"""Tests for FEAT-001 (Email & Phone Sign-Up / Login) acceptance criteria."""

from fastapi.testclient import TestClient


def test_register_with_email_and_password(client: TestClient) -> None:
    """AC: User can register with email + password."""
    response = client.post(
        "/v1/auth/register",
        json={
            "full_name": "Amaka Okafor",
            "email": "amaka@example.com",
            "password": "supersecret1",
        },
    )
    assert response.status_code == 201
    body = response.json()
    assert body["access_token"]
    assert body["refresh_token"]
    assert body["role"] == "seeker"


def test_me_returns_current_user_identity(client: TestClient) -> None:
    """GET /v1/auth/me resolves the caller's identity from their token --
    used by the Admin Web Console's session layer."""
    register = client.post(
        "/v1/auth/register",
        json={"full_name": "Amaka Okafor", "email": "me-check@example.com", "password": "supersecret1"},
    )
    token = register.json()["access_token"]

    response = client.get("/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    body = response.json()
    assert body["email"] == "me-check@example.com"
    assert body["role"] == "seeker"
    assert body["is_active"] is True


def test_me_requires_authentication(client: TestClient) -> None:
    response = client.get("/v1/auth/me")
    assert response.status_code in (401, 403)  # HTTPBearer rejects missing credentials


def test_register_duplicate_email_rejected(client: TestClient) -> None:
    client.post(
        "/v1/auth/register",
        json={"full_name": "A", "email": "dupe@example.com", "password": "supersecret1"},
    )
    response = client.post(
        "/v1/auth/register",
        json={"full_name": "B", "email": "dupe@example.com", "password": "supersecret1"},
    )
    assert response.status_code == 409


def test_phone_signup_otp_flow(client: TestClient, monkeypatch) -> None:
    """AC: User can register with phone number + OTP."""
    request_response = client.post(
        "/v1/auth/register/phone/request-otp",
        json={"full_name": "Tunde Bello", "phone_number": "+2348012345678"},
    )
    assert request_response.status_code == 202

    from app.services.auth_service import _otp_store

    otp = _otp_store["+2348012345678"]

    verify_response = client.post(
        "/v1/auth/register/phone/verify-otp",
        json={"phone_number": "+2348012345678", "otp_code": otp},
    )
    assert verify_response.status_code == 201
    assert verify_response.json()["role"] == "seeker"


def test_phone_signup_wrong_otp_rejected(client: TestClient) -> None:
    client.post(
        "/v1/auth/register/phone/request-otp",
        json={"full_name": "T", "phone_number": "+2348011111111"},
    )
    response = client.post(
        "/v1/auth/register/phone/verify-otp",
        json={"phone_number": "+2348011111111", "otp_code": "000000"},
    )
    assert response.status_code == 400


def test_login_and_session_persists_via_refresh(client: TestClient) -> None:
    """AC: User can log in and stay logged in across app restarts (refresh token)."""
    client.post(
        "/v1/auth/register",
        json={"full_name": "Ngozi", "email": "ngozi@example.com", "password": "supersecret1"},
    )
    login_response = client.post(
        "/v1/auth/login", json={"email": "ngozi@example.com", "password": "supersecret1"}
    )
    assert login_response.status_code == 200
    refresh_token = login_response.json()["refresh_token"]

    refresh_response = client.post("/v1/auth/refresh", json={"refresh_token": refresh_token})
    assert refresh_response.status_code == 200
    assert refresh_response.json()["user_id"] == login_response.json()["user_id"]


def test_login_invalid_credentials_shows_specific_error(client: TestClient) -> None:
    """AC: Invalid credentials show a clear, specific error message."""
    client.post(
        "/v1/auth/register",
        json={"full_name": "David", "email": "david@example.com", "password": "supersecret1"},
    )
    response = client.post(
        "/v1/auth/login", json={"email": "david@example.com", "password": "wrongpassword"}
    )
    assert response.status_code == 401
    assert "couldn't verify" in response.json()["detail"].lower()


def test_forgot_password_and_reset(client: TestClient) -> None:
    """AC: User can reset a forgotten password."""
    client.post(
        "/v1/auth/register",
        json={"full_name": "Amaka", "email": "reset@example.com", "password": "oldpassword1"},
    )
    forgot_response = client.post("/v1/auth/forgot-password", json={"email": "reset@example.com"})
    assert forgot_response.status_code == 202

    from app.services.auth_service import _reset_token_store

    token = next(k.split("pwreset:")[1] for k in _reset_token_store if k.startswith("pwreset:"))

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
