"""Pydantic schemas for In-App Reporting -- FEAT-009.

Mirrors dispute.py's shape: mobile-facing create request(s) plus
staff/admin-facing list/resolve schemas backing the Admin Moderation
Queue (FEAT-025).
"""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field

from app.models.report import REPORT_REASONS, REPORT_STATUSES, REPORT_TARGET_TYPES

__all__ = [
    "REPORT_REASONS",
    "REPORT_STATUSES",
    "REPORT_TARGET_TYPES",
    "ReportCreateRequest",
    "ReportOut",
    "ReportListItem",
    "ReportListResponse",
    "ReportResolveRequest",
]


class ReportCreateRequest(BaseModel):
    reason: str
    detail: str | None = Field(default=None, max_length=2000)


class ReportOut(BaseModel):
    """Returned to the mobile client after submitting a report -- just
    enough to confirm what was recorded (screens.md Screen 6's "Report
    Submitted" toast state)."""

    id: str
    target_type: str
    target_id: str
    reason: str
    status: str
    created_at: datetime


class ReportListItem(BaseModel):
    """A single report row in the Admin Moderation Queue -- carries
    `queue_item_type` so the Admin Web Console can visually/textually
    distinguish it from a "new Owner listing" review item, per FEAT-025 AC."""

    queue_item_type: str = Field(default="listing_report")
    id: str
    reporter_user_id: str
    reporter_name: str
    target_type: str
    target_id: str
    reason: str
    detail: str | None
    status: str
    created_at: datetime
    resolved_at: datetime | None
    resolution_note: str | None


class ReportListResponse(BaseModel):
    items: list[ReportListItem]
    next_cursor: str | None = None


class ReportResolveRequest(BaseModel):
    resolution_note: str = Field(min_length=1, max_length=2000)
