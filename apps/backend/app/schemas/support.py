"""Request/response schemas for FEAT-029 (General In-App Support / Help,
screens.md Screen 26). Decoupled from `app.firestore_models` per AGENTS.md's
"ORM/data models are never reused as API schemas" convention, same as
schemas/chat.py.
"""

from datetime import datetime

from pydantic import BaseModel


class SupportConversationOut(BaseModel):
    id: str
    user_id: str
    assigned_staff_id: str | None = None
    status: str
    last_message_at: datetime
    created_at: datetime
