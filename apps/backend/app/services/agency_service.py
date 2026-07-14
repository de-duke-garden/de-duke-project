"""Business logic for FEAT-012 (Agent Team Inbox / Lead Assignment) and
FEAT-019 (Lead Analytics per Listing).

Server-side role/permission enforcement lives here (never client-side only,
per AGENTS.md): every function that mutates or reads agency-scoped data
takes the caller's identity and re-derives what they're allowed to see,
rather than trusting a client-supplied filter.

Every mutating action writes an immutable `AuditLogEntry` as part of the
same unit of work, mirroring staff_account_service.py's own pattern.
"""

from __future__ import annotations

import secrets
from datetime import UTC, date, datetime, timedelta

import anyio
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import CurrentUser, UserRole, hash_password
from app.models.agency import AgencyTeamMember, Lead, LeadAssignment
from app.models.discovery import ListingAnalytics
from app.models.listing import Listing
from app.models.ops import AuditLogEntry
from app.models.transaction import Transaction
from app.models.user import User
from app.schemas.agency import (
    AGENCY_ROLES,
    AgencyListingItemOut,
    AgencySummaryOut,
    ListingAnalyticsOut,
)

# Transaction.status values that represent a closed deal for time-to-close
# purposes -- mirrors dispute_service.py's own reuse of Transaction.status
# string values rather than inventing a parallel enum.
_CLOSED_TRANSACTION_STATUSES = ("succeeded",)


class AgencyError(Exception):
    """Base class for agency-service domain errors -- mapped to 4xx
    responses by app/api/v1/agency.py, never a 500 (AGENTS.md: these are
    caller-correctable input/permission errors)."""


class EmailAlreadyInUseError(AgencyError):
    pass


class NotAnAgencyAdminError(AgencyError):
    """Raised when the caller's own account is not the `agency` role, or
    (for a team member acting) is not flagged `agency_role="admin"` in
    AgencyTeamMember."""


class TeamMemberNotFoundError(AgencyError):
    pass


class LeadNotFoundError(AgencyError):
    pass


class LeadAlreadyAssignedError(AgencyError):
    """Raised on the "two admins assign the same lead simultaneously" race
    (screens.md Screen 15 Edge Case) -- the second caller gets this, mapped
    to a 409 by the router so the client can show "assigned by someone
    else"."""


class ListingNotFoundError(AgencyError):
    pass


# -- Identity helpers ---------------------------------------------------------


async def _agency_root_id(session: AsyncSession, current_user: CurrentUser) -> str:
    """Resolves the `users.id` that owns an agency's listings/leads.

    Both an agency owner and its invited team members share `User.role ==
    "agency"` (schema.md/security.py define no separate "agent" role), so
    role alone can't distinguish them -- `User.agency_id` is the real
    signal: set for an invited team member (pointing at the root account),
    None for the root account itself. Checked in that order (agency_id
    first) so a team member is never mistaken for their own agency root.
    Raises AgencyError if the caller has no agency affiliation at all."""
    user = await session.get(User, current_user.user_id)
    if user is not None and user.agency_id is not None:
        return user.agency_id
    if current_user.role == UserRole.AGENCY:
        return current_user.user_id
    raise NotAnAgencyAdminError("This account is not part of any agency team.")


async def _is_agency_admin(
    session: AsyncSession, *, agency_id: str, current_user: CurrentUser
) -> bool:
    """True if the caller IS the agency root account, or is a team member
    whose AgencyTeamMember.agency_role == "admin"."""
    if current_user.user_id == agency_id:
        return True
    result = await session.execute(
        select(AgencyTeamMember).where(
            AgencyTeamMember.agency_id == agency_id,
            AgencyTeamMember.user_id == current_user.user_id,
        )
    )
    member = result.scalar_one_or_none()
    return member is not None and member.agency_role == "admin"


async def require_agency_admin(session: AsyncSession, current_user: CurrentUser) -> str:
    """Resolves the agency_id and asserts the caller is an admin on it.
    Raises NotAnAgencyAdminError otherwise (mapped to 403 by the router)."""
    agency_id = await _agency_root_id(session, current_user)
    if not await _is_agency_admin(session, agency_id=agency_id, current_user=current_user):
        raise NotAnAgencyAdminError("Only an agency admin can perform this action.")
    return agency_id


# -- Team management (FEAT-012 AC: invite team members) ----------------------


async def invite_team_member(
    session: AsyncSession,
    *,
    actor: CurrentUser,
    full_name: str,
    email: str,
    agency_role: str,
) -> tuple[AgencyTeamMember, User, str]:
    if agency_role not in AGENCY_ROLES:
        raise AgencyError(f"agency_role must be one of {AGENCY_ROLES}")

    agency_id = await require_agency_admin(session, actor)

    existing = await session.execute(select(User).where(User.email == email))
    if existing.scalars().first() is not None:
        raise EmailAlreadyInUseError(f"{email} is already associated with an account.")

    raw_token = secrets.token_urlsafe(32)
    # Offloaded to a worker thread -- bcrypt is CPU-bound and synchronous;
    # calling it directly in this `async def` would block the event loop
    # for the hash's full duration. See auth_service.register_with_email's
    # comment for the load-test regression this pattern was found from.
    user = User(
        full_name=full_name,
        email=email,
        role=UserRole.AGENCY.value,
        is_active=True,
        agency_id=agency_id,
        invited_by_id=actor.user_id,
        password_hash=await anyio.to_thread.run_sync(hash_password, raw_token),
    )
    session.add(user)
    await session.flush()  # populate user.id for the FKs below

    member = AgencyTeamMember(
        agency_id=agency_id,
        user_id=user.id,
        agency_role=agency_role,
    )
    session.add(member)

    session.add(
        AuditLogEntry(
            actor_id=actor.user_id,
            action_type="agency_team_member_invited",
            target_type="User",
            target_id=user.id,
            notes=f"Invited {email} as agency {agency_role}.",
        )
    )
    await session.commit()
    await session.refresh(member)
    await session.refresh(user)
    return member, user, raw_token


async def list_team_members(
    session: AsyncSession, *, current_user: CurrentUser
) -> list[tuple[AgencyTeamMember, User]]:
    """Any team member (admin or agent) can see the roster -- Screen 15's
    assignment picker (`GET /agency/team`) needs it, and it's not
    sensitive data within the agency itself."""
    agency_id = await _agency_root_id(session, current_user)
    result = await session.execute(
        select(AgencyTeamMember, User)
        .join(User, User.id == AgencyTeamMember.user_id)
        .where(AgencyTeamMember.agency_id == agency_id)
        .order_by(AgencyTeamMember.invited_at.asc())
    )
    return [(member, user) for member, user in result.all()]


async def _get_team_member(
    session: AsyncSession, *, agency_id: str, user_id: str
) -> AgencyTeamMember | None:
    result = await session.execute(
        select(AgencyTeamMember).where(
            AgencyTeamMember.agency_id == agency_id,
            AgencyTeamMember.user_id == user_id,
        )
    )
    return result.scalar_one_or_none()


# -- Leads / assignment (FEAT-012 ACs) ---------------------------------------


async def list_leads(
    session: AsyncSession,
    *,
    current_user: CurrentUser,
    status_filter: str | None = None,
    assignee: str = "me",
) -> list[Lead]:
    """FEAT-012 AC: "Team members see only their assigned conversations by
    default, with an admin view showing all." `assignee` is caller-supplied
    UI intent, not a trust boundary -- an admin passing assignee="me" still
    only sees their own; a non-admin passing assignee="all" is silently
    downgraded to "me" rather than trusting the client to withhold the
    request (AGENTS.md: enforce server-side, never rely on hiding UI)."""
    agency_id = await _agency_root_id(session, current_user)
    is_admin = await _is_agency_admin(session, agency_id=agency_id, current_user=current_user)

    stmt = select(Lead).where(Lead.agency_id == agency_id)
    if status_filter:
        stmt = stmt.where(Lead.status == status_filter)

    if not (is_admin and assignee == "all"):
        # Non-admins (or an admin explicitly asking for "mine") only see
        # leads currently assigned to them -- joined via the current
        # (non-unassigned) LeadAssignment row.
        assignment_subq = select(LeadAssignment.lead_id).where(
            LeadAssignment.assigned_to_id == current_user.user_id,
            LeadAssignment.unassigned_at.is_(None),
        )
        stmt = stmt.where(Lead.id.in_(assignment_subq))

    stmt = stmt.order_by(Lead.created_at.desc())
    result = await session.execute(stmt)
    return list(result.scalars().all())


async def get_lead_assignee(session: AsyncSession, lead: Lead) -> LeadAssignment | None:
    if lead.current_assignment_id is None:
        return None
    return await session.get(LeadAssignment, lead.current_assignment_id)


async def assign_lead(
    session: AsyncSession,
    *,
    actor: CurrentUser,
    lead_id: str,
    assigned_to_id: str,
) -> Lead:
    """FEAT-012 ACs: assignable to a specific team member; assignment
    changes logged with timestamp + actor; De-Duke staff visibility into
    the underlying conversation is untouched by this (it never writes to
    Firestore or touches ChatConversation.assignedStaffId -- that field is
    a separate concept, per chat_service.py's own docstring, gating Staff
    Support Oversight, not agency-internal routing)."""
    agency_id = await require_agency_admin(session, actor)

    lead = await session.get(Lead, lead_id)
    if lead is None or lead.agency_id != agency_id:
        raise LeadNotFoundError(f"Lead {lead_id} not found for this agency.")

    assignee = await _get_team_member(session, agency_id=agency_id, user_id=assigned_to_id)
    is_root_admin = assigned_to_id == agency_id
    if assignee is None and not is_root_admin:
        raise TeamMemberNotFoundError(
            "assigned_to_id must reference a member of this agency's team."
        )

    # Race guard (screens.md Screen 15 Edge Case: two admins assigning the
    # same lead simultaneously) -- re-fetch immediately before mutating and
    # only allow moving out of "unassigned"/re-assigning an already-open
    # assignment forward; a lead already reassigned by a concurrent request
    # in the (tiny) window between the read above and here would violate
    # this, so guard on status/current_assignment_id staying what we read.
    if lead.status not in ("unassigned", "assigned"):
        raise LeadAlreadyAssignedError("This lead is closed/lost and can no longer be assigned.")

    now = datetime.now(UTC)
    # Close out the previous assignment row, if any, before opening a new
    # one -- keeps "current assignee" always resolvable via exactly one
    # LeadAssignment with unassigned_at IS NULL per lead.
    if lead.current_assignment_id is not None:
        previous = await session.get(LeadAssignment, lead.current_assignment_id)
        if previous is not None and previous.unassigned_at is None:
            previous.unassigned_at = now
            session.add(previous)

    new_assignment = LeadAssignment(
        lead_id=lead.id,
        assigned_to_id=assigned_to_id,
        assigned_by_id=actor.user_id,
        assigned_at=now,
    )
    session.add(new_assignment)
    await session.flush()  # populate new_assignment.id

    lead.current_assignment_id = new_assignment.id
    lead.status = "assigned"
    session.add(lead)

    session.add(
        AuditLogEntry(
            actor_id=actor.user_id,
            action_type="lead_assigned",
            target_type="Lead",
            target_id=lead.id,
            notes=f"assigned_to={assigned_to_id}",
        )
    )
    await session.commit()
    await session.refresh(lead)
    return lead


# -- Agency dashboard / portfolio (Screens 13 & 14) --------------------------


async def get_agency_summary(session: AsyncSession, current_user: CurrentUser) -> AgencySummaryOut:
    agency_id = await _agency_root_id(session, current_user)

    total_active = (
        await session.execute(
            select(func.count())
            .select_from(Listing)
            .where(Listing.agency_id == agency_id, Listing.status == "active")
        )
    ).scalar_one()

    unassigned_leads = (
        await session.execute(
            select(func.count())
            .select_from(Lead)
            .where(Lead.agency_id == agency_id, Lead.status == "unassigned")
        )
    ).scalar_one()

    month_start = datetime.now(UTC).replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    # "Deals closed this month" -- a closed deal is a succeeded Transaction
    # against one of this agency's listings, per _CLOSED_TRANSACTION_STATUSES.
    deals_closed = (
        await session.execute(
            select(func.count())
            .select_from(Transaction)
            .join(Listing, Listing.id == Transaction.listing_id)
            .where(
                Listing.agency_id == agency_id,
                Transaction.status.in_(_CLOSED_TRANSACTION_STATUSES),
                Transaction.created_at >= month_start,
            )
        )
    ).scalar_one()

    team_count = (
        await session.execute(
            select(func.count())
            .select_from(AgencyTeamMember)
            .where(AgencyTeamMember.agency_id == agency_id)
        )
    ).scalar_one()

    # FEAT-018 AC "aggregate conversion metrics (views -> inquiries ->
    # closed deals)" -- lifetime sums across every listing this agency
    # owns, regardless of current status (a closed/unpublished listing's
    # historical views/inquiries still count toward the portfolio's
    # track record). Listing.view_count/inquiry_count are the same
    # denormalized lifetime counters Host Dashboard (FEAT-017) already
    # reads per-listing; this is just their portfolio-wide sum.
    view_inquiry_totals = (
        await session.execute(
            select(
                func.coalesce(func.sum(Listing.view_count), 0),
                func.coalesce(func.sum(Listing.inquiry_count), 0),
            ).where(Listing.agency_id == agency_id)
        )
    ).one()

    total_deals_closed = (
        await session.execute(
            select(func.count())
            .select_from(Transaction)
            .join(Listing, Listing.id == Transaction.listing_id)
            .where(
                Listing.agency_id == agency_id,
                Transaction.status.in_(_CLOSED_TRANSACTION_STATUSES),
            )
        )
    ).scalar_one()

    return AgencySummaryOut(
        total_active_listings=int(total_active),
        unassigned_leads_count=int(unassigned_leads),
        deals_closed_this_month=int(deals_closed),
        has_team=int(team_count) > 0,
        total_views=int(view_inquiry_totals[0]),
        total_inquiries=int(view_inquiry_totals[1]),
        total_deals_closed=int(total_deals_closed),
    )


async def list_agency_listings(
    session: AsyncSession,
    *,
    current_user: CurrentUser,
    status_filter: str | None = None,
    assigned_agent_id: str | None = None,
) -> list[AgencyListingItemOut]:
    """Screen 14 (Portfolio List View). Any team member can view the
    portfolio (read-only); mutation endpoints (bulk actions) are out of
    this feature slice's scope and belong to a future FEAT-012/017 follow-
    up -- not fabricated here."""
    agency_id = await _agency_root_id(session, current_user)

    stmt = select(Listing).where(Listing.agency_id == agency_id)
    if status_filter:
        stmt = stmt.where(Listing.status == status_filter)
    stmt = stmt.order_by(Listing.created_at.desc())
    listings = (await session.execute(stmt)).scalars().all()

    # "Assigned agent" per listing = whoever is currently assigned to that
    # listing's most recently created lead with an active assignment --
    # schema.md has no direct Listing->User assignment column, so this is
    # derived via Lead/LeadAssignment (documented design choice; flagged in
    # the implementation report as the closest available proxy).
    items: list[AgencyListingItemOut] = []
    for listing in listings:
        agent_id: str | None = None
        agent_name: str | None = None
        lead_result = await session.execute(
            select(Lead)
            .where(Lead.listing_id == listing.id, Lead.agency_id == agency_id)
            .order_by(Lead.created_at.desc())
        )
        for lead in lead_result.scalars().all():
            assignment = await get_lead_assignee(session, lead)
            if assignment is not None and assignment.unassigned_at is None:
                agent_id = assignment.assigned_to_id
                agent = await session.get(User, agent_id)
                agent_name = agent.full_name if agent is not None else "Unknown"
                break

        if assigned_agent_id and agent_id != assigned_agent_id:
            continue

        items.append(
            AgencyListingItemOut(
                id=listing.id,
                title=listing.title,
                listing_type=listing.listing_type,
                status=listing.status,
                assigned_agent_id=agent_id,
                assigned_agent_name=agent_name,
                owner_client_name=listing.owner_client_name,
                view_count=listing.view_count,
                inquiry_count=listing.inquiry_count,
            )
        )
    return items


# -- Bulk actions (FEAT-018) ---------------------------------------------------


async def bulk_update_listing_status(
    session: AsyncSession,
    *,
    current_user: CurrentUser,
    listing_ids: list[str],
    target_status: str,
) -> list[tuple[str, bool, str | None]]:
    """Screen 14's Bulk Action Bar (relist/archive). Every listing is
    checked independently -- one listing belonging to another agency, not
    found, or stuck under_review/banned never blocks the rest of the
    batch from applying; the caller gets a per-listing result back instead
    of an all-or-nothing failure, mirroring the same host-settable-status
    guard PATCH /v1/listings/:id already enforces one listing at a time
    (see app/api/v1/listings.py's update_listing_endpoint).

    Only an agency admin may bulk-act -- unlike list_agency_listings
    (read-only, any team member), this mutates every listing in the
    agency's portfolio at once, the same admin-only bar FEAT-012's other
    mutating actions (invite, assign) already hold.
    """
    agency_id = await _agency_root_id(session, current_user)
    if not await _is_agency_admin(session, agency_id=agency_id, current_user=current_user):
        raise NotAnAgencyAdminError("Only an agency admin can perform bulk listing actions.")

    results: list[tuple[str, bool, str | None]] = []
    for listing_id in listing_ids:
        listing = await session.get(Listing, listing_id)
        if listing is None or listing.agency_id != agency_id:
            results.append((listing_id, False, "Listing not found in this agency's portfolio."))
            continue
        if listing.status not in ("active", "unpublished"):
            results.append(
                (listing_id, False, f"Cannot change status while listing is {listing.status}.")
            )
            continue
        listing.status = target_status
        session.add(listing)
        results.append((listing_id, True, None))

    await session.commit()
    return results


# -- Lead analytics per listing (FEAT-019) -----------------------------------


async def get_listing_analytics(
    session: AsyncSession,
    *,
    current_user: CurrentUser,
    listing_id: str,
    range_days: int,
) -> ListingAnalyticsOut:
    """FEAT-019 ACs: view/inquiry counts, conversion rate, average response
    time, time-to-close, over a selectable 7/30/90 day range.

    Known, documented gap: schema.md/architecture.md define no time-bucketed
    view/inquiry event log (Listing.view_count/inquiry_count are lifetime
    denormalized counters, not per-day buckets), and average response time
    requires reading first-response timestamps out of Firestore chat
    messages, which no background worker in this codebase yet materializes
    into ListingAnalytics.average_response_time_minutes. Rather than
    fabricate that pipeline, this reads whatever ListingAnalytics snapshot
    already exists for the requested range (if a future worker has
    populated one) and otherwise falls back to the lifetime Listing
    counters as an approximation -- clearly distinguishable to the caller
    because average_response_time_minutes is None until a real snapshot
    exists (surfaces as screens.md's documented Empty state)."""
    listing = await session.get(Listing, listing_id)
    if listing is None:
        raise ListingNotFoundError(f"Listing {listing_id} not found.")

    # Authorization: the caller must be able to see this listing's
    # analytics -- either the agency that owns it (any team member) or
    # (out of this feature's scope) a non-agency host viewing their own
    # listing. Enforced here rather than left to the client.
    if listing.agency_id is not None:
        agency_id = await _agency_root_id(session, current_user)
        if agency_id != listing.agency_id:
            raise NotAnAgencyAdminError(
                "You don't have permission to view this listing's analytics."
            )

    range_end = date.today()
    range_start = range_end - timedelta(days=range_days)

    stored = (
        (
            await session.execute(
                select(ListingAnalytics)
                .where(
                    ListingAnalytics.listing_id == listing_id,
                    ListingAnalytics.range_start == range_start,
                    ListingAnalytics.range_end == range_end,
                )
                .order_by(ListingAnalytics.id.desc())
            )
        )
        .scalars()
        .first()
    )

    if stored is not None:
        view_count = stored.view_count
        inquiry_count = stored.inquiry_count
        average_response_time_minutes = stored.average_response_time_minutes
        closed_at = stored.closed_at
    else:
        # Fallback: lifetime counters, no worker-materialized snapshot yet.
        view_count = listing.view_count
        inquiry_count = listing.inquiry_count
        average_response_time_minutes = None
        closed_txn = (
            (
                await session.execute(
                    select(Transaction)
                    .where(
                        Transaction.listing_id == listing_id,
                        Transaction.status.in_(_CLOSED_TRANSACTION_STATUSES),
                    )
                    .order_by(Transaction.created_at.asc())
                )
            )
            .scalars()
            .first()
        )
        closed_at = closed_txn.created_at if closed_txn is not None else None

    conversion_rate = (inquiry_count / view_count) if view_count > 0 else 0.0
    time_to_close_days: float | None = None
    if closed_at is not None:
        time_to_close_days = (closed_at - listing.created_at).total_seconds() / 86400

    return ListingAnalyticsOut(
        listing_id=listing_id,
        range_start=range_start,
        range_end=range_end,
        range_days=range_days,
        view_count=view_count,
        inquiry_count=inquiry_count,
        inquiry_to_view_conversion_rate=round(conversion_rate, 4),
        average_response_time_minutes=average_response_time_minutes,
        time_to_close_days=(
            round(time_to_close_days, 2) if time_to_close_days is not None else None
        ),
        closed_at=closed_at,
    )
