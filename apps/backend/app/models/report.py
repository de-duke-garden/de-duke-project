"""Report -- FEAT-009 (In-App Reporting).

A guest-raised report against either a Listing or a chat conversation
(ChatConversation lives in Firestore, not the Primary Database -- see
app/models/__init__.py's header docstring -- so `target_id` for a
`conversation` report is a Firestore conversation document id, not an FK;
only `listing` reports carry a real Postgres FK-shaped id).

Surfaced into the same Admin Moderation Queue as new-Owner-listing review
items (FEAT-025 AC), distinguished via moderation_service's
`queue_item_type` discriminator -- see moderation_service.py.
"""

from datetime import UTC, datetime
from uuid import uuid4

from app.core.db_types import UTCDateTime
from sqlmodel import Field, SQLModel

# listing | conversation
REPORT_TARGET_TYPES = ("listing", "conversation")

# fake | scam | incorrect_info | other
REPORT_REASONS = ("fake", "scam", "incorrect_info", "other")

# open | reviewing | resolved | dismissed
REPORT_STATUSES = ("open", "reviewing", "resolved", "dismissed")


class Report(SQLModel, table=True):
    __tablename__ = "reports"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    reporter_user_id: str = Field(foreign_key="users.id", index=True)
    # listing | conversation
    target_type: str = Field(index=True)
    # Listing.id for target_type=="listing"; Firestore conversation doc id
    # for target_type=="conversation" -- never an FK constraint here since
    # conversations aren't Primary-Database rows.
    target_id: str = Field(index=True)
    # fake | scam | incorrect_info | other
    reason: str
    detail: str | None = Field(default=None)
    # open | reviewing | resolved | dismissed
    status: str = Field(default="open", index=True)
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), sa_type=UTCDateTime
    )
    resolved_at: datetime | None = Field(default=None, sa_type=UTCDateTime)
    resolved_by_user_id: str | None = Field(default=None, foreign_key="users.id")
    resolution_note: str | None = Field(default=None)
