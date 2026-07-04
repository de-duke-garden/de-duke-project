"""Tests for FEAT-030 (Data Retention & Account Deletion, NDPR Compliance)
acceptance criteria."""

from fastapi.testclient import TestClient


def _register(client: TestClient, email: str) -> str:
    response = client.post(
        "/v1/auth/register",
        json={"full_name": "Deletable User", "email": email, "password": "supersecret1"},
    )
    return response.json()["access_token"]


def test_request_deletion_explains_immediate_vs_retained(client: TestClient) -> None:
    """AC: system clearly explains what's deleted immediately vs retained."""
    token = _register(client, "delete-me@example.com")
    response = client.post(
        "/v1/account-deletion/request", headers={"Authorization": f"Bearer {token}"}
    )
    assert response.status_code == 200
    body = response.json()
    assert body["deleted_immediately"]
    assert body["anonymized_immediately"]
    assert body["retained_for_a_defined_period"]
    assert any("transaction" in item.lower() for item in body["retained_for_a_defined_period"])


def test_deletion_requires_authentication(client: TestClient) -> None:
    response = client.post("/v1/account-deletion/request")
    assert response.status_code in (401, 403)


def test_deleted_account_can_no_longer_log_in(client: TestClient) -> None:
    """Confirms the immediate profile scrub/deactivation actually takes effect."""
    token = _register(client, "gone@example.com")
    client.post("/v1/account-deletion/request", headers={"Authorization": f"Bearer {token}"})

    login_response = client.post(
        "/v1/auth/login", json={"email": "gone@example.com", "password": "supersecret1"}
    )
    # Email was scrubbed, so this now looks like an unknown account.
    assert login_response.status_code == 401
