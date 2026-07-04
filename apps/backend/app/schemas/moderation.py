"""Pydantic schemas for the moderation queue -- FEAT-025."""

from pydantic import BaseModel, Field


class ModerationQueueItemOut(BaseModel):
    listing_id: str
    listing_type: str
    title: str
    status: str
    status_reason: str | None
    host_account_id: str
    host_type: str
    created_at: str
    primary_image_url: str | None = None


class ModerationDecisionIn(BaseModel):
    reason: str = Field(min_length=1, max_length=2000)


class ModerationDecisionOut(BaseModel):
    listing_id: str
    status: str
    status_reason: str | None


class ModerationAction(str):
    APPROVE = "approve"
    BAN = "ban"


def validate_action(action: str) -> str:
    if action not in ("approve", "ban"):
        raise ValueError("action must be 'approve' or 'ban'")
    return action
