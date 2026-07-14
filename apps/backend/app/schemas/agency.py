"""Request/response contracts for FEAT-012 (Agent Team Inbox / Lead
Assignment) and FEAT-019 (Lead Analytics per Listing).

Deliberately decoupled from the `AgencyTeamMember` / `Lead` /
`LeadAssignment` / `ListingAnalytics` ORM models (AGENTS.md: ORM models are
never reused as API schemas).
"""

from __future__ import annotations

from datetime import date, datetime

from pydantic import BaseModel, Field

# Mirrors AgencyTeamMember.agency_role's documented values.
AGENCY_ROLES = ("admin", "agent")

# Mirrors Lead.status's documented values.
LEAD_STATUSES = ("unassigned", "assigned", "closed", "lost")

# screens.md Screen 16's segmented control -- the only three valid windows.
ANALYTICS_RANGE_DAYS = (7, 30, 90)


# -- Team management (FEAT-012) ----------------------------------------------


class InviteTeamMemberRequest(BaseModel):
    full_name: str = Field(min_length=1, max_length=200)
    email: str = Field(min_length=3, max_length=320)
    # admin | agent -- an agency admin inviting another admin is allowed
    # (e.g. a co-owner), matching FEAT-033's staff invite shape rather than
    # hardcoding every invitee to "agent".
    agency_role: str = Field(default="agent")


class TeamMemberOut(BaseModel):
    id: str
    user_id: str
    full_name: str
    email: str | None
    agency_role: str
    invited_at: datetime
    joined_at: datetime | None


class InviteTeamMemberResponse(BaseModel):
    member: TeamMemberOut
    invite_link: str = Field(
        description=(
            "One-time link the invitee uses to set their own password, "
            "mirroring staff_account.py's InviteStaffResponse shape. Returned "
            "directly (rather than only emailed) so this endpoint is testable "
            "without a live SES sandbox."
        )
    )


# -- Leads / assignment (FEAT-012) -------------------------------------------


class LeadOut(BaseModel):
    id: str
    conversation_id: str
    agency_id: str
    listing_id: str
    status: str
    current_assignment_id: str | None
    assigned_to_id: str | None
    assigned_to_name: str | None
    created_at: datetime


class AssignLeadRequest(BaseModel):
    assigned_to_id: str


class LeadAssignmentOut(BaseModel):
    id: str
    lead_id: str
    assigned_to_id: str
    assigned_by_id: str
    assigned_at: datetime
    unassigned_at: datetime | None


# -- Agency dashboard / portfolio ---------------------------------------------


class AgencySummaryOut(BaseModel):
    """Screen 13 (Agency Dashboard) data need. `has_team` drives the client's
    "solo agency omits team metrics gracefully" edge case (screens.md
    Screen 13 Edge Cases) rather than showing a zero-state for something
    not yet relevant."""

    total_active_listings: int
    unassigned_leads_count: int
    deals_closed_this_month: int
    has_team: bool
    # FEAT-018 AC "Portfolio view shows aggregate conversion metrics (views
    # -> inquiries -> closed deals)" -- lifetime sums across every listing
    # the agency owns (not just active ones, unlike total_active_listings
    # above), so the funnel reflects the whole portfolio's track record.
    # `deals_closed_this_month` above is this-month only; the funnel here
    # deliberately uses all-time `total_deals_closed` as its third stage so
    # the three numbers describe one consistent lifetime funnel rather than
    # mixing windows.
    total_views: int
    total_inquiries: int
    total_deals_closed: int


class AgencyListingItemOut(BaseModel):
    """Screen 14 (Portfolio List View) row shape."""

    id: str
    title: str
    listing_type: str
    status: str
    assigned_agent_id: str | None
    assigned_agent_name: str | None
    # FEAT-018 AC "originating client/owner" tagging -- an agency-entered
    # free-text label (e.g. a landlord's name), not a platform account.
    owner_client_name: str | None
    view_count: int
    inquiry_count: int


# -- Bulk actions (FEAT-018) ---------------------------------------------------

# relist -> status=active (only from unpublished); archive -> status=unpublished
# (only from active) -- the same host-settable pair PATCH /v1/listings/:id
# already enforces (app/schemas/listing.py's ListingUpdateIn), applied here
# to many listings at once rather than introducing a third status value.
BULK_LISTING_ACTIONS = ("relist", "archive")


class BulkListingActionRequest(BaseModel):
    listing_ids: list[str] = Field(min_length=1, max_length=200)
    action: str

    @property
    def target_status(self) -> str:
        return "active" if self.action == "relist" else "unpublished"


class BulkListingActionResult(BaseModel):
    listing_id: str
    success: bool
    # Populated only when success is False -- e.g. the listing wasn't
    # found, doesn't belong to this agency, or is under_review/banned and
    # therefore not eligible for a host/agency-initiated status change.
    error: str | None = None


class BulkListingActionResponse(BaseModel):
    results: list[BulkListingActionResult]


# -- Lead analytics per listing (FEAT-019) -----------------------------------


class ListingAnalyticsOut(BaseModel):
    listing_id: str
    range_start: date
    range_end: date
    range_days: int
    view_count: int
    inquiry_count: int
    inquiry_to_view_conversion_rate: float
    average_response_time_minutes: float | None
    time_to_close_days: float | None
    closed_at: datetime | None
