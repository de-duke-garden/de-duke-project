"""Tests for FEAT-026 Dispute & Refund Management -- app/services/dispute_service.py
plus the role-gate on app/api/v1/disputes.py's staff/admin-only endpoints.

Runs against an in-memory SQLite database with only the tables this
feature touches created (User, Transaction, Dispute, AuditLogEntry) --
same minimal-schema pattern as tests/test_staff_accounts.py, since the
full SQLModel.metadata includes Postgres-only GeoAlchemy2 columns SQLite
can't compile.
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncIterator
from unittest.mock import AsyncMock, patch

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.db import get_session
from app.core.security import UserRole, create_access_token, hash_password
from app.main import app
from app.models.ops import AuditLogEntry, Dispute
from app.models.transaction import Transaction
from app.models.user import User
from app.services import dispute_service
from app.services.payment_service import PaystackNotConfiguredError

pytestmark = pytest.mark.asyncio


@pytest_asyncio.fixture
async def session() -> AsyncIterator[AsyncSession]:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(
            User.metadata.create_all,
            tables=[
                User.__table__,
                Transaction.__table__,
                Dispute.__table__,
                AuditLogEntry.__table__,
            ],
        )

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


async def _make_transaction(
    session: AsyncSession, *, payer: User, payee: User, **overrides
) -> Transaction:
    defaults: dict = {
        "listing_id": f"listing-{uuid.uuid4()}",
        "payer_id": payer.id,
        "payee_id": payee.id,
        "transaction_type": "shortlet_booking",
        "gross_amount": 50_000.0,
        "commission_amount": 5_000.0,
        "net_payout_amount": 45_000.0,
        "payment_processor_reference": f"ref-{uuid.uuid4()}",
        "status": "succeeded",
    }
    defaults.update(overrides)
    txn = Transaction(**defaults)
    session.add(txn)
    await session.commit()
    await session.refresh(txn)
    return txn


@pytest_asyncio.fixture(autouse=True)
def _stub_notifications():
    """Every resolve_dispute test path fires push+email side effects --
    stub both so tests exercise dispute logic, not the notification
    stack (which has its own dedicated test suites)."""
    with (
        patch("app.services.dispute_service.push_service.notify_user", new=AsyncMock()),
        patch("app.services.dispute_service.email_service.notify_user", new=AsyncMock()),
    ):
        yield


# -- create_dispute ----------------------------------------------------------


async def test_create_dispute_success(session: AsyncSession) -> None:
    seeker = await _make_user(session, role="seeker")
    host = await _make_user(session, role="individual_host")
    txn = await _make_transaction(session, payer=seeker, payee=host)

    dispute = await dispute_service.create_dispute(
        session,
        transaction_id=txn.id,
        raised_by_id=seeker.id,
        reason="incorrect_charge",
        description="I was charged twice for the same booking.",
    )

    assert dispute.status == "open"
    assert dispute.transaction_id == txn.id
    assert dispute.raised_by_id == seeker.id


async def test_create_dispute_rejects_invalid_reason(session: AsyncSession) -> None:
    seeker = await _make_user(session, role="seeker")
    host = await _make_user(session, role="individual_host")
    txn = await _make_transaction(session, payer=seeker, payee=host)

    with pytest.raises(dispute_service.DisputeError, match="reason must be one of"):
        await dispute_service.create_dispute(
            session,
            transaction_id=txn.id,
            raised_by_id=seeker.id,
            reason="not_a_real_reason",
            description="...",
        )


async def test_create_dispute_rejects_non_participant(session: AsyncSession) -> None:
    seeker = await _make_user(session, role="seeker")
    host = await _make_user(session, role="individual_host")
    bystander = await _make_user(session, role="seeker")
    txn = await _make_transaction(session, payer=seeker, payee=host)

    with pytest.raises(dispute_service.DisputeError, match="your own transaction"):
        await dispute_service.create_dispute(
            session,
            transaction_id=txn.id,
            raised_by_id=bystander.id,
            reason="other",
            description="...",
        )


async def test_create_dispute_rejects_unknown_transaction(session: AsyncSession) -> None:
    seeker = await _make_user(session, role="seeker")

    with pytest.raises(dispute_service.DisputeError, match="Transaction not found"):
        await dispute_service.create_dispute(
            session,
            transaction_id="does-not-exist",
            raised_by_id=seeker.id,
            reason="other",
            description="...",
        )


# -- list_disputes / get_dispute ---------------------------------------------


async def test_list_disputes_filters_by_status(session: AsyncSession) -> None:
    seeker = await _make_user(session, role="seeker")
    host = await _make_user(session, role="individual_host")
    txn = await _make_transaction(session, payer=seeker, payee=host)

    open_dispute = await dispute_service.create_dispute(
        session, transaction_id=txn.id, raised_by_id=seeker.id, reason="other", description="a"
    )
    other_txn = await _make_transaction(session, payer=seeker, payee=host)
    other_dispute = await dispute_service.create_dispute(
        session,
        transaction_id=other_txn.id,
        raised_by_id=seeker.id,
        reason="other",
        description="b",
    )
    staff = await _make_user(session, role="deduke_staff")
    await dispute_service.assign_dispute(
        session, dispute=other_dispute, staff_id=staff.id, actor_id=staff.id
    )

    open_only = await dispute_service.list_disputes(session, status_filter="open")
    assert [d.id for d in open_only] == [open_dispute.id]

    under_review_only = await dispute_service.list_disputes(session, status_filter="under_review")
    assert [d.id for d in under_review_only] == [other_dispute.id]

    all_disputes = await dispute_service.list_disputes(session)
    assert len(all_disputes) == 2


# -- assign_dispute ------------------------------------------------------------


async def test_assign_dispute_sets_under_review_and_staff(session: AsyncSession) -> None:
    seeker = await _make_user(session, role="seeker")
    host = await _make_user(session, role="individual_host")
    staff = await _make_user(session, role="deduke_staff")
    txn = await _make_transaction(session, payer=seeker, payee=host)
    dispute = await dispute_service.create_dispute(
        session, transaction_id=txn.id, raised_by_id=seeker.id, reason="other", description="x"
    )

    updated = await dispute_service.assign_dispute(
        session, dispute=dispute, staff_id=staff.id, actor_id=staff.id
    )

    assert updated.assigned_staff_id == staff.id
    assert updated.status == "under_review"


async def test_assign_dispute_rejects_non_staff_target(session: AsyncSession) -> None:
    seeker = await _make_user(session, role="seeker")
    host = await _make_user(session, role="individual_host")
    txn = await _make_transaction(session, payer=seeker, payee=host)
    dispute = await dispute_service.create_dispute(
        session, transaction_id=txn.id, raised_by_id=seeker.id, reason="other", description="x"
    )

    with pytest.raises(dispute_service.DisputeError, match="Staff or Admin"):
        await dispute_service.assign_dispute(
            session, dispute=dispute, staff_id=host.id, actor_id=host.id
        )


# -- resolve_dispute -----------------------------------------------------------


async def test_resolve_dispute_without_refund(session: AsyncSession) -> None:
    seeker = await _make_user(session, role="seeker")
    host = await _make_user(session, role="individual_host")
    staff = await _make_user(session, role="deduke_staff")
    txn = await _make_transaction(session, payer=seeker, payee=host)
    dispute = await dispute_service.create_dispute(
        session, transaction_id=txn.id, raised_by_id=seeker.id, reason="other", description="x"
    )

    resolved = await dispute_service.resolve_dispute(
        session,
        dispute=dispute,
        resolution="resolved_no_refund",
        resolution_notes="Investigated, charge was correct.",
        refund_amount=None,
        actor_id=staff.id,
    )

    assert resolved.status == "resolved_no_refund"
    assert resolved.resolved_at is not None
    assert resolved.refund_amount is None

    refreshed_txn = await dispute_service.get_transaction_or_none(session, txn.id)
    assert refreshed_txn.status == "succeeded"  # untouched


async def test_resolve_dispute_with_refund_calls_paystack_and_marks_transaction_refunded(
    session: AsyncSession,
) -> None:
    seeker = await _make_user(session, role="seeker")
    host = await _make_user(session, role="individual_host")
    staff = await _make_user(session, role="deduke_staff")
    txn = await _make_transaction(session, payer=seeker, payee=host, gross_amount=20_000.0)
    dispute = await dispute_service.create_dispute(
        session,
        transaction_id=txn.id,
        raised_by_id=seeker.id,
        reason="property_not_as_described",
        description="x",
    )

    with patch(
        "app.services.dispute_service.payment_service.refund_paystack_transaction",
        new=AsyncMock(),
    ) as mock_refund:
        resolved = await dispute_service.resolve_dispute(
            session,
            dispute=dispute,
            resolution="resolved_refunded",
            resolution_notes="Confirmed, refunding in full.",
            refund_amount=20_000.0,
            actor_id=staff.id,
        )

    mock_refund.assert_awaited_once_with(
        reference=txn.payment_processor_reference, amount_kobo=2_000_000
    )
    assert resolved.status == "resolved_refunded"
    assert resolved.refund_amount == 20_000.0

    refreshed_txn = await dispute_service.get_transaction_or_none(session, txn.id)
    assert refreshed_txn.status == "refunded"


async def test_resolve_dispute_refund_requires_amount(session: AsyncSession) -> None:
    seeker = await _make_user(session, role="seeker")
    host = await _make_user(session, role="individual_host")
    staff = await _make_user(session, role="deduke_staff")
    txn = await _make_transaction(session, payer=seeker, payee=host)
    dispute = await dispute_service.create_dispute(
        session, transaction_id=txn.id, raised_by_id=seeker.id, reason="other", description="x"
    )

    with pytest.raises(dispute_service.DisputeError, match="refund_amount is required"):
        await dispute_service.resolve_dispute(
            session,
            dispute=dispute,
            resolution="resolved_refunded",
            resolution_notes="...",
            refund_amount=None,
            actor_id=staff.id,
        )


async def test_resolve_dispute_paystack_failure_leaves_dispute_open(
    session: AsyncSession,
) -> None:
    seeker = await _make_user(session, role="seeker")
    host = await _make_user(session, role="individual_host")
    staff = await _make_user(session, role="deduke_staff")
    txn = await _make_transaction(session, payer=seeker, payee=host)
    dispute = await dispute_service.create_dispute(
        session, transaction_id=txn.id, raised_by_id=seeker.id, reason="other", description="x"
    )

    with patch(
        "app.services.dispute_service.payment_service.refund_paystack_transaction",
        new=AsyncMock(side_effect=PaystackNotConfiguredError("paystack_secret_key is REPLACE_ME")),
    ):
        with pytest.raises(dispute_service.DisputeError):
            await dispute_service.resolve_dispute(
                session,
                dispute=dispute,
                resolution="resolved_refunded",
                resolution_notes="...",
                refund_amount=10_000.0,
                actor_id=staff.id,
            )

    # Dispute must remain open/unresolved -- a failed refund call must
    # never be treated as a successful resolution (AGENTS.md Payment
    # Correctness).
    still_open = await dispute_service.get_dispute(session, dispute.id)
    assert still_open.status == "open"
    assert still_open.resolved_at is None


async def test_resolve_already_resolved_dispute_raises(session: AsyncSession) -> None:
    seeker = await _make_user(session, role="seeker")
    host = await _make_user(session, role="individual_host")
    staff = await _make_user(session, role="deduke_staff")
    txn = await _make_transaction(session, payer=seeker, payee=host)
    dispute = await dispute_service.create_dispute(
        session, transaction_id=txn.id, raised_by_id=seeker.id, reason="other", description="x"
    )
    await dispute_service.resolve_dispute(
        session,
        dispute=dispute,
        resolution="resolved_no_refund",
        resolution_notes="Closed.",
        refund_amount=None,
        actor_id=staff.id,
    )

    with pytest.raises(dispute_service.DisputeError, match="already been resolved"):
        await dispute_service.resolve_dispute(
            session,
            dispute=dispute,
            resolution="resolved_no_refund",
            resolution_notes="Trying again.",
            refund_amount=None,
            actor_id=staff.id,
        )


# -- API-layer role gate (mirrors tests/test_staff_accounts.py's pattern) -----


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


async def test_seeker_can_raise_dispute_via_api(
    client: AsyncClient, session: AsyncSession
) -> None:
    seeker = await _make_user(session, role="seeker")
    host = await _make_user(session, role="individual_host")
    txn = await _make_transaction(session, payer=seeker, payee=host)

    response = await client.post(
        "/v1/disputes",
        json={
            "transaction_id": txn.id,
            "reason": "service_issue",
            "description": "Property management was unresponsive.",
        },
        headers=_auth_header(seeker),
    )

    assert response.status_code == 201
    assert response.json()["status"] == "open"


async def test_seeker_cannot_list_disputes(client: AsyncClient, session: AsyncSession) -> None:
    seeker = await _make_user(session, role="seeker")

    response = await client.get("/v1/disputes", headers=_auth_header(seeker))

    assert response.status_code == 403


async def test_seeker_cannot_resolve_disputes(
    client: AsyncClient, session: AsyncSession
) -> None:
    seeker = await _make_user(session, role="seeker")
    host = await _make_user(session, role="individual_host")
    txn = await _make_transaction(session, payer=seeker, payee=host)
    dispute = await dispute_service.create_dispute(
        session, transaction_id=txn.id, raised_by_id=seeker.id, reason="other", description="x"
    )

    response = await client.patch(
        f"/v1/disputes/{dispute.id}/resolve",
        json={"resolution": "resolved_no_refund", "resolution_notes": "n/a"},
        headers=_auth_header(seeker),
    )

    assert response.status_code == 403


async def test_staff_can_list_and_resolve_disputes_via_api(
    client: AsyncClient, session: AsyncSession
) -> None:
    seeker = await _make_user(session, role="seeker")
    host = await _make_user(session, role="individual_host")
    staff = await _make_user(session, role="deduke_staff")
    txn = await _make_transaction(session, payer=seeker, payee=host)
    dispute = await dispute_service.create_dispute(
        session, transaction_id=txn.id, raised_by_id=seeker.id, reason="other", description="x"
    )

    list_response = await client.get("/v1/disputes", headers=_auth_header(staff))
    assert list_response.status_code == 200
    assert len(list_response.json()) == 1

    resolve_response = await client.patch(
        f"/v1/disputes/{dispute.id}/resolve",
        json={"resolution": "resolved_no_refund", "resolution_notes": "Reviewed, no issue found."},
        headers=_auth_header(staff),
    )
    assert resolve_response.status_code == 200
    assert resolve_response.json()["status"] == "resolved_no_refund"
