"""Request/response schemas for FEAT-010 (Real-Time Three-Way Support Chat).

Decoupled from `app.firestore_models` per AGENTS.md's "ORM/data models are
never reused as API schemas" convention -- these are the API contracts, the
Firestore models are the storage shape.
"""

from datetime import datetime

from pydantic import BaseModel


class ChatTokenResponse(BaseModel):
    """A scoped Firebase custom auth token the client exchanges (client-side,
    via the Firebase SDK) for a Firestore ID token. Firestore security rules
    (see apps/backend/firestore.rules) read the `role` (and optionally
    `conversation_ids`) custom claims embedded in this token."""

    firebase_custom_token: str
    role: str
    expires_in_seconds: int


class StartConversationRequest(BaseModel):
    """Only a seeker (client) or a property management (host/agency) user can
    kick off a new conversation, always scoped to a specific listing so the
    backend can resolve+validate both participants server-side."""

    listing_id: str


class ChatConversationOut(BaseModel):
    id: str
    listing_id: str
    client_id: str
    property_management_id: str
    assigned_staff_id: str | None = None
    last_message_at: datetime
    created_at: datetime


class ChatUserOut(BaseModel):
    """Backs the Admin Web Console's Chat Oversight Module (screens.md
    Screen 22) resolving raw clientId/propertyManagementId/assignedStaffId
    references to display names -- see GET /v1/chat/users."""

    id: str
    full_name: str
