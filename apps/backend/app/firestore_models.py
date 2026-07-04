"""ChatConversation + ChatMessage -- schema.md.

These physically live in Google Cloud Firestore, not the Primary Database
(architecture.md, schema.md storage note) -- so they are plain Pydantic
models here, never SQLModel `table=True` classes, and are never touched by
Alembic. They exist purely so the Backend API Service has a typed shape when
it reads/writes Firestore documents for auth-token issuance and moderation
actions (the only points where the backend touches Firestore directly).
"""

from datetime import datetime

from pydantic import BaseModel


class ChatConversation(BaseModel):
    id: str
    listing_id: str
    client_id: str
    property_management_id: str
    assigned_staff_id: str | None = None
    last_message_at: datetime
    created_at: datetime


class ChatMessage(BaseModel):
    id: str
    conversation_id: str
    sender_id: str | None = None
    # client | property_management | deduke_staff | None (system messages)
    sender_role: str | None = None
    # text | system
    message_type: str
    body: str
    # sending | sent | delivered | read | failed
    delivery_status: str
    sent_at: datetime
