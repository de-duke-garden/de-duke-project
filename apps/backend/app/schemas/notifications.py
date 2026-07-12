"""Request/response DTOs for /v1/notifications -- FEAT-022 (Push
Notifications). Kept separate from app/schemas/auth.py's notification
preference schemas (email, FEAT-024) since push has its own registration
concept (device tokens) that email has no equivalent of.
"""

from pydantic import BaseModel, Field, field_validator


class RegisterPushTokenRequest(BaseModel):
    token: str = Field(min_length=1)
    # ios | android -- see app/models/push_token.py's platform comment.
    platform: str

    @field_validator("platform")
    @classmethod
    def _valid_platform(cls, v: str) -> str:
        if v not in ("ios", "android"):
            raise ValueError("platform must be 'ios' or 'android'")
        return v


class PushNotificationPreferencesResponse(BaseModel):
    """Mirrors app/schemas/auth.py's NotificationPreferencesResponse
    (email) exactly, but for push's own category set -- see
    app/models/user.py's DEFAULT_PUSH_NOTIFICATION_PREFERENCES."""

    push_notification_preferences: dict[str, bool]


class UpdatePushNotificationPreferencesRequest(BaseModel):
    """Partial update -- omitted categories are left unchanged, same
    pattern as auth.py's UpdateNotificationPreferencesRequest."""

    listings: bool | None = None
    chat: bool | None = None
    payments: bool | None = None
