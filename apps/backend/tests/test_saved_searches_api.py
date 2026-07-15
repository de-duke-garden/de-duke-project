"""API-level tests for FEAT-023's CRUD endpoints (save/edit/delete a saved
search) -- backs Screen 20 (Saved Searches) and Screen 5's "Save this
search" exit point. `SavedSearch` has no PostGIS/pgvector columns, so this
is fully exercised against the SQLite test engine per conftest.py.

Geocoding (app/services/geocoding_service.geocode_address) is patched to a
fake, network-free implementation throughout this file -- these tests must
never make a real call to Google's Geocoding API, and must stay
deterministic regardless of whether a real GOOGLE_MAPS_API_KEY happens to
be configured in the environment running them.
"""

from unittest.mock import AsyncMock, patch

import pytest
from fastapi.testclient import TestClient

from tests.conftest import mock_firebase_verify


@pytest.fixture(autouse=True)
def _fake_geocoding():
    with patch(
        "app.services.saved_search_service.geocode_address",
        AsyncMock(return_value=(6.5, 3.3)),
    ) as mock:
        yield mock


def _register_and_login(client: TestClient, email: str) -> str:
    """FEAT-001: consumer sign-in is Firebase-only now -- see
    tests.conftest.mock_firebase_verify for why this fakes an ID-token
    exchange instead of a backend-hosted register endpoint."""
    with mock_firebase_verify(uid=f"uid-{email}", email=email, name="Test Seeker"):
        response = client.post("/v1/auth/firebase-exchange", json={"id_token": "fake-token"})
    return response.json()["access_token"]


def _auth_headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_create_and_list_saved_search(client: TestClient) -> None:
    token = _register_and_login(client, "seeker1@example.com")

    create_response = client.post(
        "/v1/searches/saved",
        headers=_auth_headers(token),
        json={
            "label": "3-bed shortlets in Lekki",
            "location_query": "Lekki",
            "radius_km": 10.0,
            "listing_type": "shortlet",
            "max_price": 500000,
            "verified_only": True,
            "alerts_enabled": True,
        },
    )
    assert create_response.status_code == 201
    body = create_response.json()
    assert body["label"] == "3-bed shortlets in Lekki"
    assert body["alerts_enabled"] is True

    list_response = client.get("/v1/searches/saved", headers=_auth_headers(token))
    assert list_response.status_code == 200
    results = list_response.json()["results"]
    assert len(results) == 1
    assert results[0]["id"] == body["id"]


def test_list_saved_searches_is_scoped_to_current_user(client: TestClient) -> None:
    token_a = _register_and_login(client, "seeker-a@example.com")
    token_b = _register_and_login(client, "seeker-b@example.com")

    client.post(
        "/v1/searches/saved",
        headers=_auth_headers(token_a),
        json={"label": "A's search", "location_query": "Ikeja", "radius_km": 5.0},
    )

    response = client.get("/v1/searches/saved", headers=_auth_headers(token_b))
    assert response.status_code == 200
    assert response.json()["results"] == []


def test_toggle_alerts_switch_via_patch(client: TestClient) -> None:
    """Screen 20's alert `Switch` PATCHes just `alerts_enabled`."""
    token = _register_and_login(client, "seeker2@example.com")
    created = client.post(
        "/v1/searches/saved",
        headers=_auth_headers(token),
        json={
            "label": "Offices in Victoria Island",
            "location_query": "Victoria Island",
            "radius_km": 8.0,
        },
    ).json()
    assert created["alerts_enabled"] is True

    patched = client.patch(
        f"/v1/searches/saved/{created['id']}",
        headers=_auth_headers(token),
        json={"alerts_enabled": False},
    )
    assert patched.status_code == 200
    assert patched.json()["alerts_enabled"] is False
    # Everything else left unchanged by the partial update.
    assert patched.json()["label"] == "Offices in Victoria Island"


def test_edit_filters_via_patch(client: TestClient) -> None:
    token = _register_and_login(client, "seeker3@example.com")
    created = client.post(
        "/v1/searches/saved",
        headers=_auth_headers(token),
        json={
            "label": "Shops",
            "location_query": "Yaba",
            "radius_km": 5.0,
            "listing_type": "commercial",
        },
    ).json()

    patched = client.patch(
        f"/v1/searches/saved/{created['id']}",
        headers=_auth_headers(token),
        json={"clear_listing_type": True, "max_price": 2000000},
    )
    assert patched.status_code == 200
    body = patched.json()
    assert body["listing_type"] is None
    assert body["max_price"] == 2000000


def test_delete_saved_search(client: TestClient) -> None:
    token = _register_and_login(client, "seeker4@example.com")
    created = client.post(
        "/v1/searches/saved",
        headers=_auth_headers(token),
        json={"label": "Delete me", "location_query": "Ajah", "radius_km": 5.0},
    ).json()

    delete_response = client.delete(
        f"/v1/searches/saved/{created['id']}", headers=_auth_headers(token)
    )
    assert delete_response.status_code == 204

    list_response = client.get("/v1/searches/saved", headers=_auth_headers(token))
    assert list_response.json()["results"] == []


def test_cannot_edit_or_delete_another_users_saved_search(client: TestClient) -> None:
    token_a = _register_and_login(client, "seeker-c@example.com")
    token_b = _register_and_login(client, "seeker-d@example.com")

    created = client.post(
        "/v1/searches/saved",
        headers=_auth_headers(token_a),
        json={"label": "A's private search", "location_query": "Surulere", "radius_km": 5.0},
    ).json()

    patch_response = client.patch(
        f"/v1/searches/saved/{created['id']}",
        headers=_auth_headers(token_b),
        json={"alerts_enabled": False},
    )
    assert patch_response.status_code == 404

    delete_response = client.delete(
        f"/v1/searches/saved/{created['id']}", headers=_auth_headers(token_b)
    )
    assert delete_response.status_code == 404


def test_create_requires_authentication(client: TestClient) -> None:
    response = client.post(
        "/v1/searches/saved",
        json={"label": "No auth", "location_query": "Ikoyi", "radius_km": 5.0},
    )
    assert response.status_code in (401, 403)


def test_create_geocodes_location_query(client: TestClient, _fake_geocoding) -> None:
    token = _register_and_login(client, "seeker5@example.com")

    response = client.post(
        "/v1/searches/saved",
        headers=_auth_headers(token),
        json={"label": "Flats in Lekki", "location_query": "Lekki", "radius_km": 10.0},
    )

    assert response.status_code == 201
    _fake_geocoding.assert_awaited_once_with("Lekki")


def test_editing_location_query_re_geocodes(client: TestClient, _fake_geocoding) -> None:
    token = _register_and_login(client, "seeker6@example.com")
    created = client.post(
        "/v1/searches/saved",
        headers=_auth_headers(token),
        json={"label": "Flats", "location_query": "Lekki", "radius_km": 10.0},
    ).json()
    _fake_geocoding.reset_mock()

    client.patch(
        f"/v1/searches/saved/{created['id']}",
        headers=_auth_headers(token),
        json={"location_query": "Ikoyi"},
    )

    _fake_geocoding.assert_awaited_once_with("Ikoyi")


def test_editing_without_changing_location_query_does_not_re_geocode(
    client: TestClient, _fake_geocoding
) -> None:
    token = _register_and_login(client, "seeker7@example.com")
    created = client.post(
        "/v1/searches/saved",
        headers=_auth_headers(token),
        json={"label": "Flats", "location_query": "Lekki", "radius_km": 10.0},
    ).json()
    _fake_geocoding.reset_mock()

    client.patch(
        f"/v1/searches/saved/{created['id']}",
        headers=_auth_headers(token),
        json={"max_price": 1000000},
    )

    _fake_geocoding.assert_not_awaited()


def test_create_degrades_gracefully_when_geocoding_fails(client: TestClient) -> None:
    """A Google Geocoding outage/unconfigured key must never block saving a
    search -- geocode_address returning None just leaves the coordinates
    null (degraded substring-matching path)."""
    token = _register_and_login(client, "seeker8@example.com")

    with patch("app.services.saved_search_service.geocode_address", AsyncMock(return_value=None)):
        response = client.post(
            "/v1/searches/saved",
            headers=_auth_headers(token),
            json={"label": "Flats", "location_query": "Unresolvable Address", "radius_km": 10.0},
        )

    assert response.status_code == 201
