"""Pydantic schemas for the moderation queue -- FEAT-025."""

from pydantic import BaseModel, Field


class ModerationQueueItemOut(BaseModel):
    # FEAT-025 AC (post-FEAT-009): discriminates "new Owner listing"
    # review items from FEAT-009 report items in the same queue --
    # see app/services/moderation_service.py's QUEUE_ITEM_TYPE_* constants.
    queue_item_type: str = "new_listing_review"
    # listing_* fields are None for a conversation_report item -- a
    # reported chat conversation has no single Listing row to describe
    # (Firestore conversation ids are not Listing FKs -- see
    # app/models/report.py). Required (non-None) for new_listing_review
    # and listing_report items.
    listing_id: str | None
    listing_type: str | None
    title: str | None
    status: str | None
    status_reason: str | None
    host_account_id: str | None
    host_type: str | None
    created_at: str
    primary_image_url: str | None = None

    # Populated only for queue_item_type in (listing_report,
    # conversation_report) -- None for new_listing_review items.
    report_id: str | None = None
    report_reason: str | None = None
    report_detail: str | None = None
    reporter_user_id: str | None = None
    reporter_name: str | None = None


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
