"""Tests for FEAT-010 chat token issuance + conversation creation.

All Firebase Admin SDK calls are mocked -- these tests never require a live
Firebase project or real credentials, per the task brief.
"""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.core.security import CurrentUser, UserRole, get_current_user
from app.main import app
from app.services import chat_service as svc

# ---------------------------------------------------------------------------
# chat_service unit tests
# ---------------------------------------------------------------------------


def test_chat_role_for_maps_all_roles() -> None:
    assert svc.chat_role_for(UserRole.SEEKER) == "client"
    assert svc.chat_role_for(UserRole.INDIVIDUAL_HOST) == "property_management"
    assert svc.chat_role_for(UserRole.AGENCY) == "property_management"
    assert svc.chat_role_for(UserRole.CORPORATE) == "property_management"
    assert svc.chat_role_for(UserRole.DEDUKE_STAFF) == "deduke_staff"
    assert svc.chat_role_for(UserRole.DEDUKE_ADMIN) == "deduke_staff"


def test_issue_custom_token_raises_when_unconfigured() -> None:
    """firebase_service_account_json/firestore_project_id are REPLACE_ME in
    every test/dev environment -- the service must fail loudly, not crash on
    import or silently no-op."""
    svc._firebase_app = None
    with pytest.raises(svc.ChatServiceUnavailableError):
        svc.issue_custom_token(uid="user-1", role=UserRole.SEEKER)


def test_issue_custom_token_calls_admin_sdk_with_role_claim() -> None:
    fake_app = object()
    with (
        patch.object(svc, "_is_configured", return_value=True),
        patch.object(svc, "_get_firebase_app", return_value=fake_app),
        patch("firebase_admin.auth.create_custom_token") as mock_create_token,
    ):
        mock_create_token.return_value = b"signed-token"

        token = svc.issue_custom_token(
            uid="staff-1", role=UserRole.DEDUKE_STAFF, conversation_ids=["conv-1"]
        )

        assert token == "signed-token"
        mock_create_token.assert_called_once_with(
            "staff-1",
            {"role": "deduke_staff", "conversation_ids": ["conv-1"]},
            app=fake_app,
        )


@pytest.mark.asyncio
async def test_resolve_property_management_id_uses_agency_id_when_set() -> None:
    listing = SimpleNamespace(agency_id="agency-user-1", host_account_id="host-account-1")
    session = MagicMock()

    async def fake_get(model, pk):  # noqa: ANN001, ARG001
        return listing

    session.get = fake_get

    result = await svc.resolve_property_management_id(session, "listing-1")
    assert result == "agency-user-1"


@pytest.mark.asyncio
async def test_resolve_property_management_id_falls_back_to_host_account_user() -> None:
    listing = SimpleNamespace(agency_id=None, host_account_id="host-account-1")
    host_account = SimpleNamespace(user_id="owner-user-1")

    calls = {"n": 0}

    async def fake_get(model, pk):  # noqa: ANN001, ARG001
        calls["n"] += 1
        return listing if calls["n"] == 1 else host_account

    session = MagicMock()
    session.get = fake_get

    result = await svc.resolve_property_management_id(session, "listing-1")
    assert result == "owner-user-1"


@pytest.mark.asyncio
async def test_resolve_property_management_id_raises_when_listing_missing() -> None:
    async def fake_get(model, pk):  # noqa: ANN001, ARG001
        return None

    session = MagicMock()
    session.get = fake_get

    with pytest.raises(svc.ListingNotFoundError):
        await svc.resolve_property_management_id(session, "missing-listing")


@pytest.mark.asyncio
async def test_create_conversation_writes_expected_shape_to_firestore() -> None:
    listing = SimpleNamespace(agency_id="agency-user-1", host_account_id="host-account-1")

    async def fake_get(model, pk):  # noqa: ANN001, ARG001
        return listing

    session = MagicMock()
    session.get = fake_get

    fake_doc_ref = MagicMock()
    fake_collection = MagicMock()
    fake_collection.document.return_value = fake_doc_ref
    fake_client = MagicMock()
    fake_client.collection.return_value = fake_collection

    with patch.object(svc, "_get_firestore_client", return_value=fake_client):
        conversation = await svc.create_conversation(
            session, listing_id="listing-1", client_id="client-user-1"
        )

    assert conversation.assigned_staff_id is None
    assert conversation.client_id == "client-user-1"
    assert conversation.property_management_id == "agency-user-1"

    fake_client.collection.assert_called_once_with("conversations")
    fake_collection.document.assert_called_once_with(conversation.id)
    written = fake_doc_ref.set.call_args[0][0]
    assert written["assignedStaffId"] is None
    assert written["clientId"] == "client-user-1"
    assert written["propertyManagementId"] == "agency-user-1"
    assert written["listingId"] == "listing-1"


# ---------------------------------------------------------------------------
# Router tests (Firebase Admin SDK + DB session mocked, auth overridden)
# ---------------------------------------------------------------------------


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


def _override_current_user(role: UserRole) -> None:
    app.dependency_overrides[get_current_user] = lambda: CurrentUser(
        user_id="user-1", role=role
    )


@pytest.fixture(autouse=True)
def _clear_overrides():
    yield
    app.dependency_overrides.clear()


def test_issue_chat_token_endpoint_returns_503_when_unconfigured(client: TestClient) -> None:
    _override_current_user(UserRole.SEEKER)
    svc._firebase_app = None

    response = client.post("/v1/chat/token")

    assert response.status_code == 503


def test_issue_chat_token_endpoint_success(client: TestClient) -> None:
    _override_current_user(UserRole.SEEKER)

    with patch.object(svc, "issue_custom_token", return_value="signed-token"):
        response = client.post("/v1/chat/token")

    assert response.status_code == 200
    body = response.json()
    assert body["firebase_custom_token"] == "signed-token"
    assert body["role"] == "client"
    assert body["expires_in_seconds"] == 3600


def test_start_conversation_endpoint_404_for_missing_listing(client: TestClient) -> None:
    _override_current_user(UserRole.SEEKER)

    async def fake_create_conversation(*args, **kwargs):  # noqa: ANN002, ANN003
        raise svc.ListingNotFoundError("Listing missing-listing not found")

    with patch.object(svc, "create_conversation", side_effect=fake_create_conversation):
        response = client.post("/v1/chat/conversations", json={"listing_id": "missing-listing"})

    assert response.status_code == 404


def test_start_conversation_endpoint_success(client: TestClient) -> None:
    from datetime import UTC, datetime

    from app.firestore_models import ChatConversation

    _override_current_user(UserRole.SEEKER)

    conversation = ChatConversation(
        id="conv-1",
        listing_id="listing-1",
        client_id="user-1",
        property_management_id="host-user-1",
        assigned_staff_id=None,
        last_message_at=datetime.now(UTC),
        created_at=datetime.now(UTC),
    )

    async def fake_create_conversation(*args, **kwargs):  # noqa: ANN002, ANN003
        return conversation

    with patch.object(svc, "create_conversation", side_effect=fake_create_conversation):
        response = client.post("/v1/chat/conversations", json={"listing_id": "listing-1"})

    assert response.status_code == 201
    body = response.json()
    assert body["id"] == "conv-1"
    assert body["assigned_staff_id"] is None
    assert body["property_management_id"] == "host-user-1"
