"""Smoke test for the Foundation scaffold -- confirms the FastAPI app boots
and the health endpoints respond. Feature subagents add real tests
alongside their endpoints per AGENTS.md."""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_liveness() -> None:
    response = client.get("/health/live")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_readiness() -> None:
    response = client.get("/health/ready")
    assert response.status_code == 200
