"""Tests for FEAT-029 (General In-App Support / Help) --
app/services/chat_service.py's get_or_create_support_conversation /
notify_new_support_message, and app/api/v1/support.py's endpoints.

Mirrors tests/test_chat.py's approach for create_conversation: Firebase
Admin SDK client mocked at the `_get_firestore_client` boundary, DB session
mocked/AsyncMock'd where touched.
"""

from __future__ import annotations

from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.core.security import CurrentUser, UserRole, get_current_user
from app.main import app
from app.services import chat_service as svc

pytestmark = pytest.mark.asyncio


# ---------------------------------------------------------------------------
# get_or_create_support_conversation
# ---------------------------------------------------------------------------


async def test_creates_new_conversation_when_none_exists() -> None:
    fake_doc_ref = MagicMock()
    fake_query = MagicMock()
    fake_query.limit.return_value.stream.return_value = []  # no existing doc
    fake_collection = MagicMock()
    fake_collection.where.return_value = fake_query
    fake_collection.document.return_value = fake_doc_ref
    fake_client = MagicMock()
    fake_client.collection.return_value = fake_collection

    with patch.object(svc, "_get_firestore_client", return_value=fake_client):
        conversation = await svc.get_or_create_support_conversation(user_id="user-1")

    assert conversation.user_id == "user-1"
    assert conversation.status == "open"
    assert conversation.assigned_staff_id is None

    fake_client.collection.assert_called_once_with("support_conversations")
    fake_collection.where.assert_called_once_with("userId", "==", "user-1")
    written = fake_doc_ref.set.call_args[0][0]
    assert written["userId"] == "user-1"
    assert written["assignedStaffId"] is None
    assert written["status"] == "open"


async def test_returns_existing_conversation_instead_of_creating_duplicate() -> None:
    now = datetime.now(UTC)
    existing_doc = MagicMock()
    existing_doc.id = "existing-conversation-id"
    existing_doc.to_dict.return_value = {
        "userId": "user-1",
        "assignedStaffId": "staff-1",
        "status": "resolved",
        "lastMessageAt": now,
        "createdAt": now,
    }

    fake_query = MagicMock()
    fake_query.limit.return_value.stream.return_value = [existing_doc]
    fake_collection = MagicMock()
    fake_collection.where.return_value = fake_query
    fake_client = MagicMock()
    fake_client.collection.return_value = fake_collection

    with patch.object(svc, "_get_firestore_client", return_value=fake_client):
        conversation = await svc.get_or_create_support_conversation(user_id="user-1")

    assert conversation.id == "existing-conversation-id"
    assert conversation.status == "resolved"
    assert conversation.assigned_staff_id == "staff-1"
    # Never writes a new doc when one already exists.
    fake_collection.document.assert_not_called()


# ---------------------------------------------------------------------------
# notify_new_support_message
# ---------------------------------------------------------------------------


async def test_notify_pushes_to_owner_when_staff_sent_message() -> None:
    fake_doc = MagicMock()
    fake_doc.exists = True
    fake_doc.to_dict.return_value = {"userId": "user-1"}
    fake_collection = MagicMock()
    fake_collection.document.return_value.get.return_value = fake_doc
    fake_client = MagicMock()
    fake_client.collection.return_value = fake_collection

    session = MagicMock()

    with (
        patch.object(svc, "_get_firestore_client", return_value=fake_client),
        patch("app.services.push_service.notify_user", new=AsyncMock()) as mock_notify,
    ):
        await svc.notify_new_support_message(
            session, conversation_id="conv-1", sender_id="staff-1"
        )

    mock_notify.assert_awaited_once()
    _, kwargs = mock_notify.call_args
    assert kwargs["user_id"] == "user-1"


async def test_notify_skips_when_owner_sent_their_own_message() -> None:
    fake_doc = MagicMock()
    fake_doc.exists = True
    fake_doc.to_dict.return_value = {"userId": "user-1"}
    fake_collection = MagicMock()
    fake_collection.document.return_value.get.return_value = fake_doc
    fake_client = MagicMock()
    fake_client.collection.return_value = fake_collection

    session = MagicMock()

    with (
        patch.object(svc, "_get_firestore_client", return_value=fake_client),
        patch("app.services.push_service.notify_user", new=AsyncMock()) as mock_notify,
    ):
        await svc.notify_new_support_message(
            session, conversation_id="conv-1", sender_id="user-1"
        )

    mock_notify.assert_not_awaited()


# ---------------------------------------------------------------------------
# Router tests (Firebase Admin SDK mocked, auth overridden)
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


def test_get_or_create_endpoint_returns_503_when_unconfigured(client: TestClient) -> None:
    _override_current_user(UserRole.SEEKER)
    with patch.object(
        svc, "_get_firebase_app", side_effect=svc.ChatServiceUnavailableError("not configured")
    ):
        response = client.post("/v1/support/conversations")
    assert response.status_code == 503


def test_get_or_create_endpoint_returns_conversation(client: TestClient) -> None:
    _override_current_user(UserRole.SEEKER)
    now = datetime.now(UTC)
    fake_conversation = svc.SupportConversation(
        id="conv-1",
        user_id="user-1",
        assigned_staff_id=None,
        status="open",
        last_message_at=now,
        created_at=now,
    )
    with patch.object(
        svc, "get_or_create_support_conversation", new=AsyncMock(return_value=fake_conversation)
    ):
        response = client.post("/v1/support/conversations")
    assert response.status_code == 201
    body = response.json()
    assert body["id"] == "conv-1"
    assert body["status"] == "open"
