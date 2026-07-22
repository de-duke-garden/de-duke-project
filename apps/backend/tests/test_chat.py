"""Tests for FEAT-010 chat token issuance + conversation creation.

All Firebase Admin SDK calls are mocked -- these tests never require a live
Firebase project or real credentials, per the task brief.
"""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.core.security import CurrentUser, UserRole, get_current_user
from app.main import app
from app.services import chat_service as svc

# ---------------------------------------------------------------------------
# chat_service unit tests
# ---------------------------------------------------------------------------


def test_chat_role_for_maps_all_roles() -> None:
    assert svc.chat_role_for(UserRole.GUEST) == "client"
    assert svc.chat_role_for(UserRole.HOST) == "property_management"
    assert svc.chat_role_for(UserRole.AGENCY) == "property_management"
    assert svc.chat_role_for(UserRole.DEDUKE_STAFF) == "deduke_staff"
    assert svc.chat_role_for(UserRole.DEDUKE_ADMIN) == "deduke_staff"


def test_issue_custom_token_raises_when_unconfigured() -> None:
    """firebase_service_account_json/firestore_project_id are REPLACE_ME in
    every deployed test/CI environment -- the service must fail loudly, not
    crash on import or silently no-op. `_is_configured` is force-patched to
    False (rather than relying on ambient settings) so this test is correct
    regardless of whether the machine running it happens to have a real,
    locally-provisioned .env with actual Firebase credentials (e.g. a
    developer's own dev-project .env) -- otherwise this test is flaky
    depending on who/where it runs, and can also leave a real
    firebase_admin "[DEFAULT]" app registered process-wide for the rest of
    the test session."""
    svc._firebase_app = None
    with (
        patch.object(svc, "_is_configured", return_value=False),
        pytest.raises(svc.ChatServiceUnavailableError),
    ):
        svc.issue_custom_token(uid="user-1", role=UserRole.GUEST)


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
    # FEAT-017: create_conversation now also increments Listing.inquiry_count
    # via session.execute/commit (see app/services/chat_service.py) --
    # both must be awaitable, not plain MagicMock.
    session.execute = AsyncMock()
    session.commit = AsyncMock()

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


@pytest.mark.asyncio
async def test_resolve_user_names_short_circuits_on_no_ids() -> None:
    """No DB round-trip for an empty/all-blank id list -- a real query
    would 500 on an empty IN() clause in some SQL dialects, so this is a
    correctness guard, not just a micro-optimization."""
    session = MagicMock()
    session.execute = AsyncMock()

    result = await svc.resolve_user_names(session, [])

    assert result == []
    session.execute.assert_not_called()


# ---------------------------------------------------------------------------
# Router tests (Firebase Admin SDK + DB session mocked, auth overridden)
# ---------------------------------------------------------------------------


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


def _override_current_user(role: UserRole) -> None:
    app.dependency_overrides[get_current_user] = lambda: CurrentUser(user_id="user-1", role=role)


@pytest.fixture(autouse=True)
def _clear_overrides():
    yield
    app.dependency_overrides.clear()


def test_issue_chat_token_endpoint_returns_503_when_unconfigured(client: TestClient) -> None:
    # Same rationale as test_issue_custom_token_raises_when_unconfigured above
    # -- force-patch _is_configured rather than trust ambient .env state.
    _override_current_user(UserRole.GUEST)
    svc._firebase_app = None

    with patch.object(svc, "_is_configured", return_value=False):
        response = client.post("/v1/chat/token")

    assert response.status_code == 503


def test_issue_chat_token_endpoint_success(client: TestClient) -> None:
    _override_current_user(UserRole.GUEST)

    with patch.object(svc, "issue_custom_token", return_value="signed-token"):
        response = client.post("/v1/chat/token")

    assert response.status_code == 200
    body = response.json()
    assert body["firebase_custom_token"] == "signed-token"
    assert body["role"] == "client"
    assert body["expires_in_seconds"] == 3600


def test_start_conversation_endpoint_404_for_missing_listing(client: TestClient) -> None:
    _override_current_user(UserRole.GUEST)

    async def fake_create_conversation(*args, **kwargs):  # noqa: ANN002, ANN003
        raise svc.ListingNotFoundError("Listing missing-listing not found")

    with patch.object(svc, "create_conversation", side_effect=fake_create_conversation):
        response = client.post("/v1/chat/conversations", json={"listing_id": "missing-listing"})

    assert response.status_code == 404


def test_resolve_chat_user_names_endpoint_requires_staff(client: TestClient) -> None:
    """Chat Oversight (screens.md Screen 22) is staff/admin-only, same as
    Firestore's own isStaff() rule -- a guest requesting other users'
    names must get a 403, not a leaked directory."""
    _override_current_user(UserRole.GUEST)

    response = client.get("/v1/chat/users", params={"ids": "user-1,user-2"})

    assert response.status_code == 403


def test_resolve_chat_user_names_endpoint_returns_known_users(client: TestClient) -> None:
    _override_current_user(UserRole.DEDUKE_STAFF)

    async def fake_resolve_user_names(*args, **kwargs):  # noqa: ANN002, ANN003
        return [
            SimpleNamespace(id="user-1", full_name="Amaka Client"),
            SimpleNamespace(id="user-2", full_name="Tunde Host"),
        ]

    with patch.object(svc, "resolve_user_names", side_effect=fake_resolve_user_names):
        response = client.get("/v1/chat/users", params={"ids": "user-1,user-2,missing-user"})

    assert response.status_code == 200
    body = response.json()
    assert {u["id"]: u["full_name"] for u in body} == {
        "user-1": "Amaka Client",
        "user-2": "Tunde Host",
    }


def test_start_conversation_endpoint_success(client: TestClient) -> None:
    from datetime import UTC, datetime

    from app.firestore_models import ChatConversation

    _override_current_user(UserRole.GUEST)

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


# ---------------------------------------------------------------------------
# FEAT-001/FEAT-010 reconciliation: sync_consumer_claims / POST /chat/sync-claims
# ---------------------------------------------------------------------------


async def test_sync_consumer_claims_sets_deduke_user_id_and_role_on_firebase_account(
    session,
) -> None:
    """A consumer's real Firebase Authentication session carries neither
    the De-Duke User.id (its own uid is Firebase's, e.g. Google's) nor a
    role claim -- this bridges both onto that same Firebase account so
    firestore.rules' isParticipant()/isStaff() can be satisfied."""
    from app.models.user import User

    user = User(
        full_name="Amaka Guest",
        email="amaka-claims@example.com",
        role="guest",
        auth_provider="firebase",
        firebase_uid="firebase-uid-amaka",
    )
    session.add(user)
    await session.commit()
    await session.refresh(user)

    fake_app = object()
    with (
        patch.object(svc, "_is_configured", return_value=True),
        patch.object(svc, "_get_firebase_app", return_value=fake_app),
        patch("firebase_admin.auth.set_custom_user_claims") as mock_set_claims,
    ):
        await svc.sync_consumer_claims(session, user_id=user.id)

    mock_set_claims.assert_called_once_with(
        "firebase-uid-amaka",
        {"deduke_user_id": user.id, "role": "client"},
        app=fake_app,
    )


async def test_sync_consumer_claims_is_a_no_op_for_password_provider_account(session) -> None:
    """Staff/Admin (and any password-provider account) have no
    firebase_uid -- nothing to sync, and no error either, since the
    mobile app (this function's only caller) never has a Staff/Admin
    session to begin with."""
    from app.models.user import User

    user = User(
        full_name="Staff Member",
        email="staff-claims@example.com",
        role="deduke_staff",
        auth_provider="password",
    )
    session.add(user)
    await session.commit()
    await session.refresh(user)

    with patch("firebase_admin.auth.set_custom_user_claims") as mock_set_claims:
        await svc.sync_consumer_claims(session, user_id=user.id)

    mock_set_claims.assert_not_called()


async def test_sync_consumer_claims_no_op_when_user_not_found(session) -> None:
    with patch("firebase_admin.auth.set_custom_user_claims") as mock_set_claims:
        await svc.sync_consumer_claims(session, user_id="does-not-exist")

    mock_set_claims.assert_not_called()


def test_sync_chat_claims_endpoint_returns_204(client: TestClient) -> None:
    _override_current_user(UserRole.GUEST)

    with patch.object(svc, "sync_consumer_claims", AsyncMock(return_value=None)):
        response = client.post("/v1/chat/sync-claims")

    assert response.status_code == 204


def test_sync_chat_claims_endpoint_returns_503_when_unconfigured(client: TestClient) -> None:
    _override_current_user(UserRole.GUEST)

    with patch.object(
        svc, "sync_consumer_claims", AsyncMock(side_effect=svc.ChatServiceUnavailableError("nope"))
    ):
        response = client.post("/v1/chat/sync-claims")

    assert response.status_code == 503
