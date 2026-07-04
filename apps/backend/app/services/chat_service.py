"""Chat service -- FEAT-010 (Real-Time Three-Way Support Chat).

Handles the two backend-owned Firestore touchpoints:
  1. Issuing scoped Firebase custom auth tokens (role claims that Firestore
     security rules -- apps/backend/firestore.rules -- key off of).
  2. Server-side conversation-document creation, so `assignedStaffId=null`
     and both participant IDs are validated atomically before the document
     exists (architecture.md's Chat Data Store section).

Real-time message send/receive/listening is CLIENT-SIDE only, direct to
Firestore (mobile + admin console) -- this service never reads/writes
ChatMessage documents, only ChatConversation documents at creation time.
"""

from __future__ import annotations

import json
from datetime import UTC, datetime
from typing import Any
from uuid import uuid4

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.security import UserRole
from app.firestore_models import ChatConversation
from app.models.host_account import HostAccount
from app.models.listing import Listing

_firebase_app: Any = None


class ChatServiceUnavailableError(RuntimeError):
    """Raised when the Firebase Admin SDK isn't configured for this
    environment (firebase_service_account_json/firestore_project_id are
    still REPLACE_ME)."""


class ListingNotFoundError(ValueError):
    """Raised when a listing (or its host account) referenced by a
    StartConversationRequest can't be resolved."""


def _is_configured() -> bool:
    settings = get_settings()
    return (
        settings.firebase_service_account_json != "REPLACE_ME"
        and settings.firestore_project_id != "REPLACE_ME"
    )


def _get_firebase_app() -> Any:
    """Lazily initializes the Firebase Admin SDK app. Guarded so importing
    this module -- or booting the whole app with unconfigured creds in dev/CI
    -- never raises. The error only surfaces when a chat endpoint is actually
    invoked without real credentials.
    """
    global _firebase_app
    if _firebase_app is not None:
        return _firebase_app

    if not _is_configured():
        raise ChatServiceUnavailableError(
            "Firebase Admin SDK is not configured (firebase_service_account_json/"
            "firestore_project_id are REPLACE_ME) -- chat is unavailable in this "
            "environment until real Firebase credentials are provisioned."
        )

    import firebase_admin
    from firebase_admin import credentials

    settings = get_settings()
    cred_info = json.loads(settings.firebase_service_account_json)
    cred = credentials.Certificate(cred_info)
    _firebase_app = firebase_admin.initialize_app(
        cred, {"projectId": settings.firestore_project_id}
    )
    return _firebase_app


def _get_firestore_client() -> Any:
    from firebase_admin import firestore

    return firestore.client(_get_firebase_app())


# Maps a De-Duke `User.role` onto the chat-role claim Firestore security
# rules understand: client | property_management | deduke_staff.
_ROLE_CLAIM_MAP: dict[UserRole, str] = {
    UserRole.SEEKER: "client",
    UserRole.INDIVIDUAL_HOST: "property_management",
    UserRole.AGENCY: "property_management",
    UserRole.CORPORATE: "property_management",
    UserRole.DEDUKE_STAFF: "deduke_staff",
    UserRole.DEDUKE_ADMIN: "deduke_staff",
}


def chat_role_for(role: UserRole) -> str:
    return _ROLE_CLAIM_MAP[role]


def issue_custom_token(
    *, uid: str, role: UserRole, conversation_ids: list[str] | None = None
) -> str:
    """Issues a Firebase custom auth token carrying a `role` claim (and an
    optional `conversation_ids` allowlist) that firestore.rules reads.
    Raises ChatServiceUnavailableError if Firebase Admin SDK creds are
    unconfigured.
    """
    from firebase_admin import auth as firebase_auth

    app = _get_firebase_app()
    claims: dict[str, Any] = {"role": chat_role_for(role)}
    if conversation_ids is not None:
        claims["conversation_ids"] = conversation_ids
    token = firebase_auth.create_custom_token(uid, claims, app=app)
    return token.decode("utf-8") if isinstance(token, bytes) else token


async def resolve_property_management_id(session: AsyncSession, listing_id: str) -> str:
    """Walks Listing -> HostAccount.user_id (or Listing.agency_id if set) to
    find the user_id representing "the property management side" of a
    listing's chat -- schema.md's ChatConversation.propertyManagementId.
    """
    listing = await session.get(Listing, listing_id)
    if listing is None:
        raise ListingNotFoundError(f"Listing {listing_id} not found")

    if listing.agency_id:
        return listing.agency_id

    host_account = await session.get(HostAccount, listing.host_account_id)
    if host_account is None:
        raise ListingNotFoundError(
            f"HostAccount {listing.host_account_id} for listing {listing_id} not found"
        )
    return host_account.user_id


async def create_conversation(
    session: AsyncSession, *, listing_id: str, client_id: str
) -> ChatConversation:
    """Server-side conversation creation via the Firebase Admin SDK -- the
    ONLY point where a conversation document is written, guaranteeing
    `assignedStaffId=null` and validated participant IDs atomically
    (architecture.md Chat Data Store; design decision documented in the
    FEAT-010 task brief: creation is low-frequency/moderation-adjacent, so it
    goes through the backend rather than being client-authored).
    """
    property_management_id = await resolve_property_management_id(session, listing_id)

    now = datetime.now(UTC)
    conversation = ChatConversation(
        id=str(uuid4()),
        listing_id=listing_id,
        client_id=client_id,
        property_management_id=property_management_id,
        assigned_staff_id=None,
        last_message_at=now,
        created_at=now,
    )

    client = _get_firestore_client()
    doc_ref = client.collection("conversations").document(conversation.id)
    doc_ref.set(
        {
            "listingId": conversation.listing_id,
            "clientId": conversation.client_id,
            "propertyManagementId": conversation.property_management_id,
            "assignedStaffId": conversation.assigned_staff_id,
            "lastMessageAt": conversation.last_message_at,
            "createdAt": conversation.created_at,
        }
    )

    return conversation
