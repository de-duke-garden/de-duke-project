"""PushToken -- FEAT-022 (Push Notifications). Not in schema.md's entity
transcription (confirmed gap, same tier as User.email_notification_preferences'
own backfill note) -- a device's FCM registration token, so
app/services/push_service.py knows where to actually deliver a
notification for a given user.

A user can have multiple tokens (multiple devices signed into the same
account) -- this is deliberately NOT a single column on User.
"""

from datetime import UTC, datetime
from uuid import uuid4

from app.core.db_types import UTCDateTime
from sqlmodel import Field, SQLModel


class PushToken(SQLModel, table=True):
    __tablename__ = "push_tokens"

    id: str = Field(default_factory=lambda: str(uuid4()), primary_key=True)
    user_id: str = Field(foreign_key="users.id", index=True)

    # The FCM registration token itself. Unique -- if the same token gets
    # re-registered (app reinstall, token refresh delivered twice), it's
    # an upsert against this column, never a duplicate row that would
    # cause the same device to receive a notification twice.
    token: str = Field(unique=True, index=True)

    # ios | android -- informational only today (FCM's send API doesn't
    # need this), kept for a future platform-specific payload difference
    # (e.g. APNs-specific fields) without a migration at that point.
    platform: str

    created_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), sa_type=UTCDateTime
    )
    updated_at: datetime = Field(
        default_factory=lambda: datetime.now(UTC), sa_type=UTCDateTime
    )
