"""API-level tests for FEAT-020 share endpoints
(app/api/v1/share.py).

Generate/revoke require auth (mirrors test_moderation_api.py's role-guard
pattern); the public by-token GET must work with **no** Authorization
header at all -- that's the entire point of Screen 18 (external,
unauthenticated view). These tests route through the two routers directly
via a minimal FastAPI app rather than app.main.app, since app.main.app does
not yet mount app/api/v1/share.py's routers (see the Implementor report:
the orchestrator still needs to add the two `include_router` lines to
app/api/v1/__init__.py before these endpoints are reachable at their real
`/v1/...` paths). Once that wiring lands, these same assertions hold
against `app.main.app` unchanged.
"""

from __future__ import annotations

from unittest.mock import AsyncMock, patch

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.v1.share import listing_share_router, public_share_router
from app.core.security import UserRole, create_access_token

app = FastAPI()
app.include_router(listing_share_router, prefix="/v1/listings")
app.include_router(public_share_router, prefix="/v1/share")

client = TestClient(app)


def _token(role: UserRole = UserRole.AGENCY) -> str:
    return create_access_token(user_id="user-1", role=role)


def test_generate_share_requires_auth() -> None:
    response = client.post("/v1/listings/listing-1/share")
    assert response.status_code in (401, 403)


def test_revoke_share_requires_auth() -> None:
    response = client.delete("/v1/listings/listing-1/share/some-token")
    assert response.status_code in (401, 403)


def test_generate_share_success_with_auth() -> None:
    with patch(
        "app.api.v1.share.create_share",
        AsyncMock(
            return_value=type(
                "S", (), {"share_token": "tok-abc", "listing_id": "listing-1", "expires_at": None}
            )()
        ),
    ):
        response = client.post(
            "/v1/listings/listing-1/share",
            headers={"Authorization": f"Bearer {_token()}"},
        )
    assert response.status_code == 201
    body = response.json()
    assert body["share_token"] == "tok-abc"
    assert body["listing_id"] == "listing-1"


def test_revoke_share_forbidden_for_non_owner() -> None:
    from app.services.share_service import ShareForbiddenError

    with patch("app.api.v1.share.revoke_share", AsyncMock(side_effect=ShareForbiddenError())):
        response = client.delete(
            "/v1/listings/listing-1/share/tok-abc",
            headers={"Authorization": f"Bearer {_token()}"},
        )
    assert response.status_code == 403


def test_public_share_view_requires_no_auth() -> None:
    """The whole point of Screen 18 -- must succeed with zero credentials."""
    fake_summary = {
        "listing_id": "listing-1",
        "title": "Sunny Office Suite",
        "listing_type": "commercial",
        "location_city": "Lagos",
        "location_state": "Lagos",
        "location_address_line": "1 Broad Street",
        "price": 500000.0,
        "price_label": "lease",
        "key_terms": ["office"],
        "verification_status": "verified",
        "primary_image_url": None,
        "listing_is_active": True,
    }
    with patch(
        "app.api.v1.share.resolve_public_summary",
        AsyncMock(return_value=("ok", fake_summary)),
    ):
        response = client.get("/v1/share/tok-abc")  # no Authorization header at all

    assert response.status_code == 200
    assert response.json()["listing_id"] == "listing-1"


def test_public_share_revoked_returns_status_body() -> None:
    with patch(
        "app.api.v1.share.resolve_public_summary",
        AsyncMock(return_value=("revoked", None)),
    ):
        response = client.get("/v1/share/tok-revoked")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "revoked"
    assert "no longer available" in body["message"]


def test_public_share_expired_returns_status_body() -> None:
    with patch(
        "app.api.v1.share.resolve_public_summary",
        AsyncMock(return_value=("expired", None)),
    ):
        response = client.get("/v1/share/tok-expired")

    assert response.status_code == 200
    assert response.json()["status"] == "expired"


def test_public_share_not_found_returns_status_body() -> None:
    with patch(
        "app.api.v1.share.resolve_public_summary",
        AsyncMock(return_value=("not_found", None)),
    ):
        response = client.get("/v1/share/does-not-exist")

    assert response.status_code == 200
    assert response.json()["status"] == "not_found"
