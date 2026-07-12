"""Tests for FEAT-034 (ops_analytics_service.py) and FEAT-035
(business_analytics_service.py), plus the role gate on
app/api/v1/analytics.py (Staff+Admin for /operations, Admin-only for
/business). Same minimal-schema SQLite pattern as test_dispute_service.py
-- only the tables these two services actually touch are created.
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncIterator
from datetime import UTC, datetime, timedelta

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import JSON, Column, DateTime, Float, Integer, MetaData, String, Table
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.db import get_session
from app.core.security import UserRole, create_access_token, hash_password
from app.main import app
from app.models.host_account import HostAccount
from app.models.listing import Listing
from app.models.ops import Dispute
from app.models.transaction import Transaction
from app.models.user import User
from app.services import business_analytics_service, ops_analytics_service

pytestmark = pytest.mark.asyncio

# Listing.__table__ has a GeoAlchemy2 Geography column (location_point)
# that plain SQLite (no spatialite extension) can't create -- same
# limitation conftest.py's _sqlite_safe_tables works around by excluding
# the WHOLE listings table. This suite actually needs real Listing rows
# (moderation queue / active listings aggregates), so instead of excluding
# it, this is a hand-built physical "listings" table with every column
# Listing declares EXCEPT location_point. The real `Listing` ORM class is
# still used for every query in ops_analytics_service.py/
# business_analytics_service.py -- those only ever SELECT specific
# columns (never location_point), so the generated SQL only references
# columns that genuinely exist on this physical table. Test data is
# inserted via this Core table directly (not `session.add(Listing(...))`,
# which -- being an ORM flush of every mapped column -- would try to
# write location_point=NULL and fail the same way table creation would).
_sqlite_metadata = MetaData()
_listings_table = Table(
    "listings",
    _sqlite_metadata,
    Column("id", String, primary_key=True),
    Column("host_account_id", String),
    Column("agency_id", String, nullable=True),
    Column("listing_type", String),
    Column("title", String),
    Column("description", String),
    Column("location_latitude", Float),
    Column("location_longitude", Float),
    Column("location_address_line", String),
    Column("location_city", String),
    Column("location_state", String),
    Column("amenities", JSON, nullable=True),
    Column("status", String),
    Column("status_reason", String, nullable=True),
    Column("view_count", Integer),
    Column("created_at", DateTime(timezone=True)),
    Column("updated_at", DateTime(timezone=True)),
    Column("inquiry_count", Integer),
)


@pytest_asyncio.fixture
async def session() -> AsyncIterator[AsyncSession]:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(
            User.metadata.create_all,
            tables=[
                User.__table__,
                HostAccount.__table__,
                Dispute.__table__,
                Transaction.__table__,
            ],
        )
        await conn.run_sync(_sqlite_metadata.create_all)

    factory = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    async with factory() as sess:
        yield sess
    await engine.dispose()


async def _make_user(session: AsyncSession, *, role: str) -> User:
    user = User(
        full_name=f"Test {role}",
        email=f"{role}-{uuid.uuid4()}@example.com",
        role=role,
        is_active=True,
        password_hash=hash_password("irrelevant-password-123"),
    )
    session.add(user)
    await session.commit()
    await session.refresh(user)
    return user


async def _make_host_account(
    session: AsyncSession, *, user: User, host_type: str, status: str = "verified"
) -> HostAccount:
    account = HostAccount(
        user_id=user.id,
        host_type=host_type,
        host_photo_url="https://example.com/photo.jpg",
        bio="Test bio",
        status=status,
    )
    session.add(account)
    await session.commit()
    await session.refresh(account)
    return account


async def _make_listing(session: AsyncSession, *, host_account: HostAccount, **overrides) -> str:
    """Inserts via the hand-built `_listings_table` Core table (see this
    module's header comment) rather than `session.add(Listing(...))` --
    returns the new row's id. Callers that need to read it back use the
    real `Listing` ORM class/service functions, same as production code."""
    now = datetime.now(UTC)
    defaults: dict = {
        "id": str(uuid.uuid4()),
        "host_account_id": host_account.id,
        "agency_id": None,
        "listing_type": "shortlet",
        "title": "Test listing",
        "description": "A place to stay.",
        "location_latitude": 6.5,
        "location_longitude": 3.3,
        "location_address_line": "1 Test St",
        "location_city": "Lagos",
        "location_state": "Lagos",
        "amenities": [],
        "status": "under_review",
        "status_reason": None,
        "view_count": 0,
        "created_at": now,
        "updated_at": now,
        "inquiry_count": 0,
    }
    defaults.update(overrides)
    await session.execute(_listings_table.insert().values(**defaults))
    await session.commit()
    return defaults["id"]


async def _make_transaction(session: AsyncSession, *, payer: User, payee: User, **overrides) -> Transaction:
    defaults: dict = {
        "listing_id": f"listing-{uuid.uuid4()}",
        "payer_id": payer.id,
        "payee_id": payee.id,
        "transaction_type": "shortlet_booking",
        "gross_amount": 10_000.0,
        "commission_amount": 1_000.0,
        "net_payout_amount": 9_000.0,
        "status": "succeeded",
    }
    defaults.update(overrides)
    txn = Transaction(**defaults)
    session.add(txn)
    await session.commit()
    await session.refresh(txn)
    return txn


# -- ops_analytics_service ----------------------------------------------------


async def test_moderation_queue_stats_counts_only_moderatable_statuses(
    session: AsyncSession,
) -> None:
    host_user = await _make_user(session, role="individual_host")
    host_account = await _make_host_account(session, user=host_user, host_type="owner")
    await _make_listing(session, host_account=host_account, status="under_review")
    await _make_listing(session, host_account=host_account, status="flagged")
    await _make_listing(session, host_account=host_account, status="active")  # not in queue

    stats = await ops_analytics_service.moderation_queue_stats(session)

    assert stats["queue_size"] == 2
    assert stats["by_host_type"]["owner"]["count"] == 2
    assert stats["avg_age_hours"] >= 0


async def test_host_verification_stats_counts_only_in_review(session: AsyncSession) -> None:
    user1 = await _make_user(session, role="individual_host")
    user2 = await _make_user(session, role="agency")
    await _make_host_account(session, user=user1, host_type="owner", status="in_review")
    await _make_host_account(session, user=user2, host_type="agent", status="verified")

    stats = await ops_analytics_service.host_verification_stats(session)

    assert stats["queue_size"] == 1
    assert "owner" in stats["by_host_type"]
    assert "agent" not in stats["by_host_type"]


async def test_dispute_stats_computes_avg_resolution_time(session: AsyncSession) -> None:
    seeker = await _make_user(session, role="seeker")
    host = await _make_user(session, role="individual_host")
    txn = await _make_transaction(session, payer=seeker, payee=host)

    now = datetime.now(UTC)
    resolved = Dispute(
        transaction_id=txn.id,
        raised_by_id=seeker.id,
        reason="other",
        description="x",
        status="resolved_no_refund",
        created_at=now - timedelta(hours=10),
        resolved_at=now,
    )
    still_open = Dispute(
        transaction_id=txn.id,
        raised_by_id=seeker.id,
        reason="other",
        description="y",
        status="open",
    )
    session.add(resolved)
    session.add(still_open)
    await session.commit()

    stats = await ops_analytics_service.dispute_stats(session)

    assert stats["open_count"] == 1
    assert stats["resolved_count"] == 1
    assert 9.9 <= stats["avg_resolution_hours"] <= 10.1


async def test_booking_hold_stats_computes_conversion_and_expiry_rates(
    session: AsyncSession,
) -> None:
    seeker = await _make_user(session, role="seeker")
    host = await _make_user(session, role="individual_host")
    await _make_transaction(session, payer=seeker, payee=host, status="succeeded")
    await _make_transaction(session, payer=seeker, payee=host, status="succeeded")
    await _make_transaction(session, payer=seeker, payee=host, status="expired")
    await _make_transaction(session, payer=seeker, payee=host, status="held")

    stats = await ops_analytics_service.booking_hold_stats(session)

    assert stats["total_holds"] == 4
    assert stats["hold_to_payment_conversion_rate"] == 0.5
    assert stats["hold_expiry_rate"] == 0.25


async def test_staff_workload_counts_open_assigned_disputes(session: AsyncSession) -> None:
    seeker = await _make_user(session, role="seeker")
    host = await _make_user(session, role="individual_host")
    staff = await _make_user(session, role="deduke_staff")
    txn = await _make_transaction(session, payer=seeker, payee=host)

    session.add(
        Dispute(
            transaction_id=txn.id,
            raised_by_id=seeker.id,
            reason="other",
            description="x",
            status="under_review",
            assigned_staff_id=staff.id,
        )
    )
    session.add(
        Dispute(
            transaction_id=txn.id,
            raised_by_id=seeker.id,
            reason="other",
            description="y",
            status="open",
            assigned_staff_id=None,
        )
    )
    await session.commit()

    workload = await ops_analytics_service.staff_workload(session)

    assert workload == {staff.id: 1}


async def test_operations_dashboard_support_inbox_is_explicitly_none(
    session: AsyncSession,
) -> None:
    """FEAT-034: support inbox metrics live in Firestore, unreachable from
    this Primary-Database-only service -- must be None, never fabricated."""
    dashboard = await ops_analytics_service.get_operations_dashboard(session)
    assert dashboard["support_inbox"] is None


# -- business_analytics_service -----------------------------------------------


async def test_signups_by_role(session: AsyncSession) -> None:
    await _make_user(session, role="seeker")
    await _make_user(session, role="seeker")
    await _make_user(session, role="individual_host")

    counts = await business_analytics_service.signups_by_role(session)

    assert counts["seeker"] == 2
    assert counts["individual_host"] == 1


async def test_active_listings_breakdown(session: AsyncSession) -> None:
    host_user = await _make_user(session, role="individual_host")
    host_account = await _make_host_account(session, user=host_user, host_type="owner")
    await _make_listing(
        session, host_account=host_account, status="active", listing_type="shortlet",
        location_city="Lagos",
    )
    await _make_listing(
        session, host_account=host_account, status="under_review", listing_type="commercial",
        location_city="Abuja",
    )

    breakdown = await business_analytics_service.active_listings_breakdown(session)

    assert breakdown["by_status"]["active"] == 1
    assert breakdown["by_status"]["under_review"] == 1
    assert breakdown["by_city"] == {"Lagos": 1}  # only the active one


async def test_revenue_breakdown_only_counts_succeeded_transactions(
    session: AsyncSession,
) -> None:
    seeker = await _make_user(session, role="seeker")
    host = await _make_user(session, role="individual_host")
    await _make_transaction(
        session, payer=seeker, payee=host, status="succeeded",
        gross_amount=100_000.0, commission_amount=10_000.0,
    )
    await _make_transaction(session, payer=seeker, payee=host, status="held", gross_amount=50_000.0)

    revenue = await business_analytics_service.revenue_breakdown(session)

    assert revenue["total_gross_transaction_value"] == 100_000.0
    assert revenue["total_commission_revenue"] == 10_000.0
    assert revenue["overall_take_rate"] == 0.1


async def test_business_dashboard_leakage_and_agency_tier_are_explicitly_none(
    session: AsyncSession,
) -> None:
    """FEAT-035: leakage rate (FEAT-016) and Agency Tier (Phase 3) don't
    exist yet -- must be None, never fabricated."""
    dashboard = await business_analytics_service.get_business_dashboard(session)
    assert dashboard["leakage_rate"] is None
    assert dashboard["agency_tier"] is None


# -- API-layer role gate -------------------------------------------------------


@pytest_asyncio.fixture
async def client(session: AsyncSession) -> AsyncIterator[AsyncClient]:
    async def override_get_session() -> AsyncIterator[AsyncSession]:
        yield session

    app.dependency_overrides[get_session] = override_get_session
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()


def _auth_header(user: User) -> dict[str, str]:
    token = create_access_token(user_id=user.id, role=UserRole(user.role))
    return {"Authorization": f"Bearer {token}"}


async def test_seeker_cannot_view_operations_dashboard(
    client: AsyncClient, session: AsyncSession
) -> None:
    seeker = await _make_user(session, role="seeker")
    response = await client.get("/v1/analytics/operations", headers=_auth_header(seeker))
    assert response.status_code == 403


async def test_staff_can_view_operations_but_not_business_dashboard(
    client: AsyncClient, session: AsyncSession
) -> None:
    staff = await _make_user(session, role="deduke_staff")

    ops_response = await client.get("/v1/analytics/operations", headers=_auth_header(staff))
    assert ops_response.status_code == 200

    business_response = await client.get("/v1/analytics/business", headers=_auth_header(staff))
    assert business_response.status_code == 403


async def test_admin_can_view_both_dashboards(client: AsyncClient, session: AsyncSession) -> None:
    admin = await _make_user(session, role="deduke_admin")

    ops_response = await client.get("/v1/analytics/operations", headers=_auth_header(admin))
    assert ops_response.status_code == 200

    business_response = await client.get("/v1/analytics/business", headers=_auth_header(admin))
    assert business_response.status_code == 200
