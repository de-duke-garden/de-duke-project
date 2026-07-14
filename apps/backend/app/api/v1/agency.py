"""FEAT-012 (Agent Team Inbox / Lead Assignment) + FEAT-019 (Lead Analytics
per Listing) endpoints -- screens.md Screens 13-16.

Router stays thin; all logic (including role/permission checks) lives in
app.services.agency_service per AGENTS.md. Mounted at `/agency` (see
app/api/v1/__init__.py) except `/agency/listings/{id}/analytics`, which
mirrors screens.md Screen 16's documented mobile route
`/agency/listings/:id/analytics` exactly.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.db import get_session
from app.core.security import CurrentUser, get_current_user
from app.schemas.agency import (
    ANALYTICS_RANGE_DAYS,
    BULK_LISTING_ACTIONS,
    AgencyListingItemOut,
    AgencySummaryOut,
    AssignLeadRequest,
    BulkListingActionRequest,
    BulkListingActionResponse,
    BulkListingActionResult,
    InviteTeamMemberRequest,
    InviteTeamMemberResponse,
    LeadOut,
    ListingAnalyticsOut,
    TeamMemberOut,
)
from app.services import agency_service
from app.services.email_service import send_transactional_email

router = APIRouter()

# Reuses STAFF_INVITE's exact template shape (full_name + invite_link) --
# an agency team member's first-access email needs the same content, no
# separate template is warranted for this.
_AGENCY_TEAM_INVITE_TEMPLATE = "agency_team_invite"


def _member_out(member, user) -> TeamMemberOut:  # noqa: ANN001
    return TeamMemberOut(
        id=member.id,
        user_id=user.id,
        full_name=user.full_name,
        email=user.email,
        agency_role=member.agency_role,
        invited_at=member.invited_at,
        joined_at=member.joined_at,
    )


def _handle_agency_error(exc: agency_service.AgencyError) -> HTTPException:
    if isinstance(exc, agency_service.NotAnAgencyAdminError):
        return HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc))
    if isinstance(
        exc,
        (
            agency_service.TeamMemberNotFoundError,
            agency_service.LeadNotFoundError,
            agency_service.ListingNotFoundError,
        ),
    ):
        return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    if isinstance(exc, agency_service.EmailAlreadyInUseError):
        return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
    if isinstance(exc, agency_service.LeadAlreadyAssignedError):
        return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
    return HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))


# -- Team management ----------------------------------------------------------


@router.get("/team", response_model=list[TeamMemberOut])
async def list_team(
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[TeamMemberOut]:
    try:
        members = await agency_service.list_team_members(session, current_user=current_user)
    except agency_service.AgencyError as exc:
        raise _handle_agency_error(exc) from exc
    return [_member_out(member, user) for member, user in members]


@router.post(
    "/team/invite", response_model=InviteTeamMemberResponse, status_code=status.HTTP_201_CREATED
)
async def invite_team_member(
    payload: InviteTeamMemberRequest,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> InviteTeamMemberResponse:
    try:
        member, user, raw_token = await agency_service.invite_team_member(
            session,
            actor=current_user,
            full_name=payload.full_name,
            email=payload.email,
            agency_role=payload.agency_role,
        )
    except agency_service.AgencyError as exc:
        raise _handle_agency_error(exc) from exc

    # Fixed bug: this previously reused admin_console_url (a Staff/Admin-
    # only web tool) -- agency team members accept their invite in the
    # MOBILE app instead (see mobile_app_invite_base_url's docstring).
    mobile_app_url = get_settings().mobile_app_invite_base_url.rstrip("/")
    invite_link = f"{mobile_app_url}/accept-invite?token={raw_token}&uid={user.id}"

    if user.email:
        await send_transactional_email(
            to=user.email,
            template=_AGENCY_TEAM_INVITE_TEMPLATE,
            context={"full_name": user.full_name, "invite_link": invite_link},
        )

    return InviteTeamMemberResponse(member=_member_out(member, user), invite_link=invite_link)


# -- Leads / assignment --------------------------------------------------------


@router.get("/leads", response_model=list[LeadOut])
async def list_leads(
    status: str | None = None,
    assignee: str = "me",
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[LeadOut]:
    """`status=unassigned` backs Screen 15 (Unassigned Leads Inbox);
    `assignee=all` (admin-only, enforced server-side) + no status filter
    backs the admin's "all conversations" view."""
    try:
        leads = await agency_service.list_leads(
            session, current_user=current_user, status_filter=status, assignee=assignee
        )
    except agency_service.AgencyError as exc:
        raise _handle_agency_error(exc) from exc

    items: list[LeadOut] = []
    for lead in leads:
        assignment = await agency_service.get_lead_assignee(session, lead)
        assigned_to_name = None
        if assignment is not None:
            from app.models.user import User

            assignee_user = await session.get(User, assignment.assigned_to_id)
            assigned_to_name = assignee_user.full_name if assignee_user is not None else "Unknown"
        items.append(
            LeadOut(
                id=lead.id,
                conversation_id=lead.conversation_id,
                agency_id=lead.agency_id,
                listing_id=lead.listing_id,
                status=lead.status,
                current_assignment_id=lead.current_assignment_id,
                assigned_to_id=assignment.assigned_to_id if assignment else None,
                assigned_to_name=assigned_to_name,
                created_at=lead.created_at,
            )
        )
    return items


@router.patch("/leads/{lead_id}/assign", response_model=LeadOut)
async def assign_lead(
    lead_id: str,
    payload: AssignLeadRequest,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> LeadOut:
    try:
        lead = await agency_service.assign_lead(
            session, actor=current_user, lead_id=lead_id, assigned_to_id=payload.assigned_to_id
        )
    except agency_service.AgencyError as exc:
        raise _handle_agency_error(exc) from exc

    from app.models.user import User

    assignee_user = await session.get(User, payload.assigned_to_id)
    return LeadOut(
        id=lead.id,
        conversation_id=lead.conversation_id,
        agency_id=lead.agency_id,
        listing_id=lead.listing_id,
        status=lead.status,
        current_assignment_id=lead.current_assignment_id,
        assigned_to_id=payload.assigned_to_id,
        assigned_to_name=assignee_user.full_name if assignee_user is not None else "Unknown",
        created_at=lead.created_at,
    )


# -- Dashboard / portfolio (Screens 13 & 14) -----------------------------------


@router.get("/summary", response_model=AgencySummaryOut)
async def get_summary(
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> AgencySummaryOut:
    try:
        return await agency_service.get_agency_summary(session, current_user)
    except agency_service.AgencyError as exc:
        raise _handle_agency_error(exc) from exc


@router.get("/listings", response_model=list[AgencyListingItemOut])
async def get_agency_listings(
    status: str | None = None,
    assigned_agent_id: str | None = None,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> list[AgencyListingItemOut]:
    try:
        return await agency_service.list_agency_listings(
            session,
            current_user=current_user,
            status_filter=status,
            assigned_agent_id=assigned_agent_id,
        )
    except agency_service.AgencyError as exc:
        raise _handle_agency_error(exc) from exc


# -- Bulk actions (FEAT-018, Screen 14 Bulk Action Bar) ------------------------


@router.post("/listings/bulk-action", response_model=BulkListingActionResponse)
async def bulk_listing_action(
    payload: BulkListingActionRequest,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> BulkListingActionResponse:
    if payload.action not in BULK_LISTING_ACTIONS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"action must be one of {BULK_LISTING_ACTIONS}",
        )
    try:
        results = await agency_service.bulk_update_listing_status(
            session,
            current_user=current_user,
            listing_ids=payload.listing_ids,
            target_status=payload.target_status,
        )
    except agency_service.AgencyError as exc:
        raise _handle_agency_error(exc) from exc

    return BulkListingActionResponse(
        results=[
            BulkListingActionResult(listing_id=listing_id, success=success, error=error)
            for listing_id, success, error in results
        ]
    )


# -- Lead analytics per listing (FEAT-019, Screen 16) --------------------------


@router.get("/listings/{listing_id}/analytics", response_model=ListingAnalyticsOut)
async def get_listing_analytics(
    listing_id: str,
    range: int = 30,  # noqa: A002 -- matches screens.md's documented `?range=` query param name
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> ListingAnalyticsOut:
    if range not in ANALYTICS_RANGE_DAYS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"range must be one of {ANALYTICS_RANGE_DAYS}",
        )
    try:
        return await agency_service.get_listing_analytics(
            session, current_user=current_user, listing_id=listing_id, range_days=range
        )
    except agency_service.AgencyError as exc:
        raise _handle_agency_error(exc) from exc
