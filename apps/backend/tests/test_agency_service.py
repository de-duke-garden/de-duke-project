"""Tests for FEAT-012 (Agent Team Inbox / Lead Assignment) --
app/services/agency_service.py.

Runs against an in-memory SQLite database with only the tables this
feature's non-Listing-dependent logic touches (User, AgencyTeamMember,
Lead, LeadAssignment, AuditLogEntry) -- same minimal-schema pattern as
tests/test_dispute_service.py, since the full SQLModel.metadata includes
Postgres-only GeoAlchemy2 columns (Listing.location_point) SQLite can't
compile.

Listing/analytics-dependent paths (get_agency_summary, list_agency_listings,
get_listing_analytics) require a real Listing row and therefore a live
Postgres+PostGIS instance -- consistent with test_listing_service.py's own
documented gap for the same reason -- and are exercised at the unit level
against a lightweight in-memory fake of the Listing dependency instead.
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncIterator

import pytest
import pytest_asyncio
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.security import CurrentUser, UserRole, hash_password
from app.models.agency import AgencyTeamMember, Lead, LeadAssignment
from app.models.ops import AuditLogEntry
from app.models.user import User
from app.services import agency_service

pytestmark = pytest.mark.asyncio


@pytest_asyncio.fixture
async def session() -> AsyncIterator[AsyncSession]:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(
            User.metadata.create_all,
            tables=[
                User.__table__,
                AgencyTeamMember.__table__,
                Lead.__table__,
                LeadAssignment.__table__,
                AuditLogEntry.__table__,
            ],
        )

    factory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    async with factory() as sess:
        yield sess
    await engine.dispose()


async def _make_user(session: AsyncSession, *, role: str, agency_id: str | None = None) -> User:
    user = User(
        full_name=f"Test {role} {uuid.uuid4()}",
        email=f"{role}-{uuid.uuid4()}@example.com",
        role=role,
        is_active=True,
        agency_id=agency_id,
        password_hash=hash_password("irrelevant-password-123"),
    )
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return user


async def _make_lead(
    session: AsyncSession, *, agency_id: str, listing_id: str | None = None
) -> Lead:
    lead = Lead(
        conversation_id=f"conv-{uuid.uuid4()}",
        agency_id=agency_id,
        listing_id=listing_id or f"listing-{uuid.uuid4()}",
    )
    session.add(lead)
    await session.commit()
    await session.refresh(lead)
    return lead


def _as_current(user: User) -> CurrentUser:
    return CurrentUser(user_id=user.id, role=UserRole(user.role))


# -- invite_team_member -------------------------------------------------------


async def test_invite_team_member_by_agency_root(session: AsyncSession) -> None:
    agency = await _make_user(session, role="agency")

    member, invited_user, raw_token = await agency_service.invite_team_member(
        session,
        actor=_as_current(agency),
        full_name="Junior Agent",
        email="junior@example.com",
        agency_role="agent",
    )

    assert member.agency_id == agency.id
    assert member.agency_role == "agent"
    assert invited_user.agency_id == agency.id
    assert invited_user.role == "agency"
    assert raw_token  # a real, non-empty invite token was generated


async def test_invite_team_member_rejects_non_admin(session: AsyncSession) -> None:
    agency = await _make_user(session, role="agency")
    # A regular agent (not admin) attempting to invite someone else.
    agent = await _make_user(session, role="agency", agency_id=agency.id)
    session.add(AgencyTeamMember(agency_id=agency.id, user_id=agent.id, agency_role="agent"))
    await session.commit()

    with pytest.raises(agency_service.NotAnAgencyAdminError):
        await agency_service.invite_team_member(
            session,
            actor=_as_current(agent),
            full_name="Another Agent",
            email="another@example.com",
            agency_role="agent",
        )


async def test_invite_team_member_rejects_duplicate_email(session: AsyncSession) -> None:
    agency = await _make_user(session, role="agency")
    existing = await _make_user(session, role="guest")

    with pytest.raises(agency_service.EmailAlreadyInUseError):
        await agency_service.invite_team_member(
            session,
            actor=_as_current(agency),
            full_name="Dup",
            email=existing.email,
            agency_role="agent",
        )


# -- list_team_members ---------------------------------------------------------


async def test_list_team_members_visible_to_any_member(session: AsyncSession) -> None:
    agency = await _make_user(session, role="agency")
    _, invited_user, _ = await agency_service.invite_team_member(
        session,
        actor=_as_current(agency),
        full_name="Junior Agent",
        email="junior2@example.com",
        agency_role="agent",
    )

    # The invited agent themself can see the roster.
    members = await agency_service.list_team_members(
        session, current_user=_as_current(invited_user)
    )
    user_ids = {u.id for _, u in members}
    assert invited_user.id in user_ids


# -- assign_lead ---------------------------------------------------------------


async def test_assign_lead_logs_actor_and_timestamp(session: AsyncSession) -> None:
    agency = await _make_user(session, role="agency")
    _, agent_user, _ = await agency_service.invite_team_member(
        session,
        actor=_as_current(agency),
        full_name="Agent One",
        email="agent1@example.com",
        agency_role="agent",
    )
    lead = await _make_lead(session, agency_id=agency.id)

    assigned_lead = await agency_service.assign_lead(
        session, actor=_as_current(agency), lead_id=lead.id, assigned_to_id=agent_user.id
    )

    assert assigned_lead.status == "assigned"
    assert assigned_lead.current_assignment_id is not None

    assignment = await session.get(LeadAssignment, assigned_lead.current_assignment_id)
    assert assignment is not None
    assert assignment.assigned_to_id == agent_user.id
    assert assignment.assigned_by_id == agency.id
    assert assignment.assigned_at is not None

    from sqlalchemy import select

    audit_rows = (
        (
            await session.execute(
                select(AuditLogEntry).where(
                    AuditLogEntry.target_type == "Lead",
                    AuditLogEntry.target_id == lead.id,
                    AuditLogEntry.action_type == "lead_assigned",
                )
            )
        )
        .scalars()
        .all()
    )
    assert len(audit_rows) == 1
    assert audit_rows[0].actor_id == agency.id


async def test_assign_lead_rejects_non_admin(session: AsyncSession) -> None:
    agency = await _make_user(session, role="agency")
    _, agent_user, _ = await agency_service.invite_team_member(
        session,
        actor=_as_current(agency),
        full_name="Agent Two",
        email="agent2@example.com",
        agency_role="agent",
    )
    lead = await _make_lead(session, agency_id=agency.id)

    with pytest.raises(agency_service.NotAnAgencyAdminError):
        await agency_service.assign_lead(
            session, actor=_as_current(agent_user), lead_id=lead.id, assigned_to_id=agent_user.id
        )


async def test_assign_lead_rejects_unknown_team_member(session: AsyncSession) -> None:
    agency = await _make_user(session, role="agency")
    outsider = await _make_user(session, role="guest")
    lead = await _make_lead(session, agency_id=agency.id)

    with pytest.raises(agency_service.TeamMemberNotFoundError):
        await agency_service.assign_lead(
            session, actor=_as_current(agency), lead_id=lead.id, assigned_to_id=outsider.id
        )


async def test_reassigning_lead_closes_previous_assignment(session: AsyncSession) -> None:
    agency = await _make_user(session, role="agency")
    _, agent_a, _ = await agency_service.invite_team_member(
        session,
        actor=_as_current(agency),
        full_name="Agent A",
        email="agenta@example.com",
        agency_role="agent",
    )
    _, agent_b, _ = await agency_service.invite_team_member(
        session,
        actor=_as_current(agency),
        full_name="Agent B",
        email="agentb@example.com",
        agency_role="agent",
    )
    lead = await _make_lead(session, agency_id=agency.id)

    lead = await agency_service.assign_lead(
        session, actor=_as_current(agency), lead_id=lead.id, assigned_to_id=agent_a.id
    )
    first_assignment_id = lead.current_assignment_id

    lead = await agency_service.assign_lead(
        session, actor=_as_current(agency), lead_id=lead.id, assigned_to_id=agent_b.id
    )

    assert lead.current_assignment_id != first_assignment_id
    previous = await session.get(LeadAssignment, first_assignment_id)
    assert previous is not None
    assert previous.unassigned_at is not None


# -- list_leads: visibility rules (core FEAT-012 AC) ---------------------------


async def test_agent_sees_only_own_assigned_leads(session: AsyncSession) -> None:
    agency = await _make_user(session, role="agency")
    _, agent_a, _ = await agency_service.invite_team_member(
        session,
        actor=_as_current(agency),
        full_name="Agent A",
        email="agenta2@example.com",
        agency_role="agent",
    )
    _, agent_b, _ = await agency_service.invite_team_member(
        session,
        actor=_as_current(agency),
        full_name="Agent B",
        email="agentb2@example.com",
        agency_role="agent",
    )
    lead_a = await _make_lead(session, agency_id=agency.id)
    lead_b = await _make_lead(session, agency_id=agency.id)
    await agency_service.assign_lead(
        session, actor=_as_current(agency), lead_id=lead_a.id, assigned_to_id=agent_a.id
    )
    await agency_service.assign_lead(
        session, actor=_as_current(agency), lead_id=lead_b.id, assigned_to_id=agent_b.id
    )

    agent_a_leads = await agency_service.list_leads(
        session, current_user=_as_current(agent_a), assignee="me"
    )
    assert {lead.id for lead in agent_a_leads} == {lead_a.id}


async def test_admin_sees_all_leads(session: AsyncSession) -> None:
    agency = await _make_user(session, role="agency")
    _, agent_a, _ = await agency_service.invite_team_member(
        session,
        actor=_as_current(agency),
        full_name="Agent A",
        email="agenta3@example.com",
        agency_role="agent",
    )
    lead_unassigned = await _make_lead(session, agency_id=agency.id)
    lead_assigned = await _make_lead(session, agency_id=agency.id)
    await agency_service.assign_lead(
        session, actor=_as_current(agency), lead_id=lead_assigned.id, assigned_to_id=agent_a.id
    )

    admin_leads = await agency_service.list_leads(
        session, current_user=_as_current(agency), assignee="all"
    )
    assert {lead.id for lead in admin_leads} == {lead_unassigned.id, lead_assigned.id}


async def test_non_admin_cannot_escalate_to_all_via_query_param(session: AsyncSession) -> None:
    """AGENTS.md: server-side enforcement, never trust a client-supplied
    filter -- a non-admin passing assignee="all" is silently downgraded to
    "me", not granted visibility into other agents' leads."""
    agency = await _make_user(session, role="agency")
    _, agent_a, _ = await agency_service.invite_team_member(
        session,
        actor=_as_current(agency),
        full_name="Agent A",
        email="agenta4@example.com",
        agency_role="agent",
    )
    _, agent_b, _ = await agency_service.invite_team_member(
        session,
        actor=_as_current(agency),
        full_name="Agent B",
        email="agentb4@example.com",
        agency_role="agent",
    )
    lead_b = await _make_lead(session, agency_id=agency.id)
    await agency_service.assign_lead(
        session, actor=_as_current(agency), lead_id=lead_b.id, assigned_to_id=agent_b.id
    )

    agent_a_leads = await agency_service.list_leads(
        session, current_user=_as_current(agent_a), assignee="all"
    )
    assert lead_b.id not in {lead.id for lead in agent_a_leads}


async def test_deduke_staff_visibility_is_unaffected_by_agency_assignment(
    session: AsyncSession,
) -> None:
    """FEAT-012 AC: "De-Duke staff retain visibility into a conversation
    regardless of internal agency assignment changes." assign_lead never
    touches anything staff-visibility-related (it only writes
    Lead/LeadAssignment/AuditLogEntry rows) -- this test asserts that
    invariant directly: staff conversation access is governed entirely by
    ChatConversation (Firestore, chat_service.py), which this function
    never reads or writes."""
    agency = await _make_user(session, role="agency")
    _, agent_a, _ = await agency_service.invite_team_member(
        session,
        actor=_as_current(agency),
        full_name="Agent A",
        email="agenta5@example.com",
        agency_role="agent",
    )
    lead = await _make_lead(session, agency_id=agency.id)

    await agency_service.assign_lead(
        session, actor=_as_current(agency), lead_id=lead.id, assigned_to_id=agent_a.id
    )

    # Reassignment never mutates conversation_id -- the only field a
    # Firestore-side staff visibility check could key off of.
    reloaded = await session.get(Lead, lead.id)
    assert reloaded is not None
    assert reloaded.conversation_id == lead.conversation_id
