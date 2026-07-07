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


def test_readiness_healthy() -> None:
    """Both dependencies (SQLite standing in for the Primary Database in
    tests, fakeredis standing in for the Cache) are reachable."""
    response = client.get("/health/ready")
    assert response.status_code == 200
    body = response.json()
    assert body == {"status": "ok", "checks": {"database": True, "cache": True}}


def test_readiness_degraded_when_cache_unreachable(monkeypatch) -> None:
    """A task that can't reach the Cache must fail its readiness check
    (architecture.md Health Checks) rather than reporting healthy -- the
    ALB should pull it out of rotation, not keep routing to it."""

    def _broken_client():
        raise ConnectionError("simulated Redis outage")

    monkeypatch.setattr("app.main.cache.get_redis_client", _broken_client)

    response = client.get("/health/ready")
    assert response.status_code == 503
    body = response.json()
    assert body["status"] == "degraded"
    assert body["checks"] == {"database": True, "cache": False}
