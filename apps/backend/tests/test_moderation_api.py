"""API-level tests for moderation endpoints that don't require a live DB --
they exercise the role-based access guard, which fails fast before any
database session is used (FEAT-025, FEAT-033 role enforcement)."""

from fastapi.testclient import TestClient

from app.core.security import UserRole, create_access_token
from app.main import app

client = TestClient(app)


def _token(role: UserRole) -> str:
    return create_access_token(user_id="user-1", role=role)


def test_queue_requires_auth() -> None:
    response = client.get("/v1/moderation/queue")
    assert response.status_code == 403 or response.status_code == 401


def test_queue_rejects_non_staff_role() -> None:
    token = _token(UserRole.SEEKER)
    response = client.get("/v1/moderation/queue", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 403


def test_approve_rejects_non_staff_role() -> None:
    token = _token(UserRole.INDIVIDUAL_HOST)
    response = client.post(
        "/v1/moderation/some-listing-id/approve",
        json={"reason": "looks good"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 403


def test_ban_requires_reason() -> None:
    token = _token(UserRole.DEDUKE_STAFF)
    response = client.post(
        "/v1/moderation/some-listing-id/ban",
        json={"reason": ""},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 422
