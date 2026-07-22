"""Chat service -- FEAT-010 (Real-Time Three-Way Support Chat).

Handles the two backend-owned Firestore touchpoints:
  1. Issuing scoped Firebase custom auth tokens (role claims that Firestore
     security rules -- apps/backend/firestore.rules -- key off of).
  2. Server-side conversation-document creation, so `assignedStaffId=null`
     and both participant IDs are validated atomically before the document
     exists (architecture.md's Chat Data Store section).

Real-time message send/receive/listening is CLIENT-SIDE only, direct to
Firestore (mobile + admin console) -- this service itself never reads/writes
ChatMessage documents, only ChatConversation documents at creation time.

Documented exception: app/workers/listing_response_time_worker.py (FEAT-019)
reads ChatMessage documents read-only, for analytics purposes only (average
first-response-time per listing), via this module's `_get_firestore_client`
helper -- it never writes a message and is not part of the real-time
send/receive path.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any
from uuid import uuid4

import anyio
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import firebase as firebase_core
from app.core.security import UserRole
from app.firestore_models import ChatConversation, SupportConversation
from app.models.host_account import HostAccount
from app.models.listing import Listing
from app.models.user import User

# Kept as a module-level global (rather than only living in
# app.core.firebase) so existing tests that reset it directly
# (`svc._firebase_app = None`) keep working -- see that module's
# `reset_cached_app_for_tests`, which this mirrors.
_firebase_app: Any = None


class ChatServiceUnavailableError(RuntimeError):
    """Raised when the Firebase Admin SDK isn't configured for this
    environment (firebase_service_account_json/firestore_project_id are
    still REPLACE_ME)."""


class ListingNotFoundError(ValueError):
    """Raised when a listing (or its host account) referenced by a
    StartConversationRequest can't be resolved."""


def _is_configured() -> bool:
    return firebase_core.is_configured()


def _get_firebase_app() -> Any:
    """Lazily initializes the Firebase Admin SDK app (delegating to the
    shared app.core.firebase singleton, also used by auth_service.py for
    FEAT-001 Firebase ID token verification -- both consume the same
    Firebase project). Guarded so importing this module -- or booting the
    whole app with unconfigured creds in dev/CI -- never raises. The error
    only surfaces when a chat endpoint is actually invoked without real
    credentials.
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

    _firebase_app = firebase_core.get_firebase_app()
    return _firebase_app


def _get_firestore_client() -> Any:
    from firebase_admin import firestore

    return firestore.client(_get_firebase_app())


# Maps a De-Duke `User.role` onto the chat-role claim Firestore security
# rules understand: client | property_management | deduke_staff.
_ROLE_CLAIM_MAP: dict[UserRole, str] = {
    UserRole.GUEST: "client",
    UserRole.HOST: "property_management",
    UserRole.AGENCY: "property_management",
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


async def sync_consumer_claims(session: AsyncSession, *, user_id: str) -> None:
    """FEAT-001/FEAT-010 reconciliation: a consumer's REAL Firebase
    Authentication session (Google/email/phone, FEAT-001) doubles as
    their Firestore identity -- the backend never mints a separate
    custom-token identity for them (see this module's docstring on the
    two touchpoints, and `issue_custom_token` above, which remains
    Staff/Admin-only). But that real session's `uid` is Firebase's own
    (Google's, etc.), NOT this user's De-Duke `User.id` -- and it carries
    no `role` claim at all -- while `firestore.rules` (isParticipant,
    isSupportOwner) and every `clientId`/`propertyManagementId`/`userId`/
    `senderId` field in Firestore are keyed on the De-Duke `User.id`.
    Firestore's security rules therefore can't be satisfied by
    `request.auth.uid` for these accounts at all; they need a
    `deduke_user_id` custom claim mapping the Firebase identity to the
    De-Duke one, plus the `role` claim `isStaff()`/`chat_role_for` expect.

    Sets both claims on `user.firebase_uid` via the Firebase Admin SDK.
    Called by the mobile client (`POST /v1/chat/sync-claims`, via
    ChatRepository.ensureSignedIn()) every time chat is entered -- cheap
    and idempotent, so it self-heals both a brand-new sign-in (which
    never carried these claims to begin with) and a stale claim after a
    role change (FEAT-003) without requiring the user to sign out and
    back in. A no-op for a `password`-provider account (Staff/Admin, who
    never reach this -- the mobile app has no Staff/Admin session at
    all) or a `firebase`-provider account with no `firebase_uid` yet
    (shouldn't occur, but defensive).
    """
    user = await session.get(User, user_id)
    if user is None or user.firebase_uid is None:
        return

    from firebase_admin import auth as firebase_auth

    app = _get_firebase_app()
    claims: dict[str, Any] = {
        "deduke_user_id": user.id,
        "role": chat_role_for(UserRole(user.role)),
    }
    # set_custom_user_claims makes a real network call to Firebase's
    # Identity Toolkit API (unlike create_custom_token above, which just
    # signs a JWT locally) -- offloaded to a worker thread for the same
    # reason auth_service.exchange_firebase_token offloads verify_id_token:
    # a blocking call inside an `async def` stalls the whole event loop.
    await anyio.to_thread.run_sync(
        lambda: firebase_auth.set_custom_user_claims(user.firebase_uid, claims, app=app)
    )


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

    # FEAT-017 (Host Dashboard) AC: listing cards show inquiry counts. A
    # new conversation against a listing IS the "inquiry" -- see
    # app/models/listing.py's inquiry_count comment. Incremented only
    # after the Firestore write above succeeds (if that raised, we'd
    # never reach here), so a failed conversation creation never inflates
    # the count.
    await session.execute(
        update(Listing)
        .where(Listing.id == listing_id)
        .values(inquiry_count=Listing.inquiry_count + 1)
    )
    await session.commit()

    from app.services import analytics_service

    await analytics_service.track_event(
        event_name=analytics_service.CHAT_STARTED,
        user_id=client_id,
        properties={"listing_id": listing_id, "conversation_id": conversation.id},
    )

    return conversation


async def notify_new_message(
    session: AsyncSession, *, conversation_id: str, sender_id: str
) -> None:
    """FEAT-022 AC: "User receives a push notification for new chat
    messages when app is backgrounded." Real-time message send is
    CLIENT-SIDE direct to Firestore (this module's own header docstring)
    -- the Backend API Service never sees a message write happen, so it
    cannot trigger a push from that write the way it can for e.g. a
    booking/payment event it processes itself.

    Design decision (not specified by architecture.md, which doesn't
    address chat-push triggering mechanics): the SENDING client calls
    POST /v1/chat/conversations/{id}/notify immediately after its own
    Firestore write succeeds (see chat_repository.dart's sendMessage).
    This function then reads the conversation doc (already has Firestore
    Admin access via _get_firestore_client, same as create_conversation)
    to resolve the OTHER participant(s) -- never the sender -- and pushes
    to them. Deliberately excludes assigned_staff_id from push targets:
    De-Duke Staff work through the Admin Web Console's Chat Oversight
    Module, not push notifications on a personal device.
    """
    client = _get_firestore_client()
    doc = client.collection("conversations").document(conversation_id).get()
    if not doc.exists:
        return
    data = doc.to_dict() or {}

    recipients = {data.get("clientId"), data.get("propertyManagementId")}
    recipients.discard(sender_id)
    recipients.discard(None)

    from app.services import push_service

    for recipient_id in recipients:
        await push_service.notify_user(
            session,
            user_id=recipient_id,
            template=push_service.NEW_CHAT_MESSAGE,
            context={"conversation_id": conversation_id},
        )


async def get_or_create_support_conversation(*, user_id: str) -> SupportConversation:
    """FEAT-029 (General In-App Support / Help, screens.md Screen 26) --
    each user has AT MOST ONE support conversation ever (a durable inbox
    thread, not a one-off), so this is idempotent: a repeat call returns
    the existing conversation instead of creating a duplicate. Mirrors
    create_conversation's "backend is the only writer of the parent
    conversation document" design, for the same reason (guarantees
    userId is validated and assignedStaffId starts null).
    """
    client = _get_firestore_client()
    collection = client.collection("support_conversations")

    existing = list(collection.where("userId", "==", user_id).limit(1).stream())
    if existing:
        doc = existing[0]
        data = doc.to_dict() or {}
        return SupportConversation(
            id=doc.id,
            user_id=data["userId"],
            assigned_staff_id=data.get("assignedStaffId"),
            status=data.get("status", "open"),
            last_message_at=data["lastMessageAt"],
            created_at=data["createdAt"],
        )

    now = datetime.now(UTC)
    conversation = SupportConversation(
        id=str(uuid4()),
        user_id=user_id,
        assigned_staff_id=None,
        status="open",
        last_message_at=now,
        created_at=now,
    )
    collection.document(conversation.id).set(
        {
            "userId": conversation.user_id,
            "assignedStaffId": conversation.assigned_staff_id,
            "status": conversation.status,
            "lastMessageAt": conversation.last_message_at,
            "createdAt": conversation.created_at,
        }
    )
    return conversation


async def notify_new_support_message(
    session: AsyncSession, *, conversation_id: str, sender_id: str
) -> None:
    """Support's equivalent of notify_new_message. The recipient is
    whichever side did NOT send this message: if the user sent it, no one
    specific is pushed (staff work the Support Inbox in the Admin Web
    Console, same "no push to staff" reasoning as notify_new_message's
    docstring); if staff sent it, the owning user gets a push."""
    client = _get_firestore_client()
    doc = client.collection("support_conversations").document(conversation_id).get()
    if not doc.exists:
        return
    data = doc.to_dict() or {}

    user_id = data.get("userId")
    if user_id is None or user_id == sender_id:
        return

    from app.services import push_service

    await push_service.notify_user(
        session,
        user_id=user_id,
        template=push_service.NEW_CHAT_MESSAGE,
        context={"conversation_id": conversation_id},
    )


async def resolve_user_names(session: AsyncSession, user_ids: list[str]) -> list[User]:
    """Batch name lookup for the Admin Web Console's Chat Oversight Module
    (screens.md Screen 22) -- ChatConversation's clientId/propertyManagementId/
    assignedStaffId are raw User.id references (Firestore has no join), so
    the console previously showed bare UUIDs for all three instead of
    names. One query for the whole visible conversation list's ids rather
    than N one-at-a-time lookups (dispute_service.get_user_name_or_unknown
    is the single-id equivalent, used where only one id is ever needed).
    Silently drops unknown/deleted ids rather than erroring -- the caller
    falls back to "Unknown" per id it doesn't get a name back for."""
    unique_ids = {uid for uid in user_ids if uid}
    if not unique_ids:
        return []
    result = await session.execute(select(User).where(User.id.in_(unique_ids)))
    return list(result.scalars().all())
