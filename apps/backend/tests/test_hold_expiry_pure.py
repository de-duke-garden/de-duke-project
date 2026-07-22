"""FEAT-032 -- pure-logic tests for hold-expiry eligibility that don't
require a DB session (the DB-touching `expire_stale_holds` transition
itself is covered conceptually by test_booking_concurrency.py's skip
notes; it needs a live Postgres instance for `with_for_update()` semantics)."""

from datetime import UTC, datetime, timedelta

from app.models.transaction import Transaction
from app.services.booking_service import is_hold_active


def test_is_hold_active_true_before_expiry() -> None:
    txn = Transaction(
        listing_id="l1",
        payer_id="p1",
        payee_id="p2",
        transaction_type="shortlet_booking",
        gross_amount=100.0,
        commission_amount=0.0,
        net_payout_amount=100.0,
        status="held",
        hold_expires_at=datetime.now(UTC) + timedelta(minutes=5),
    )
    assert is_hold_active(txn) is True


def test_is_hold_active_false_after_expiry() -> None:
    txn = Transaction(
        listing_id="l1",
        payer_id="p1",
        payee_id="p2",
        transaction_type="shortlet_booking",
        gross_amount=100.0,
        commission_amount=0.0,
        net_payout_amount=100.0,
        status="held",
        hold_expires_at=datetime.now(UTC) - timedelta(minutes=1),
    )
    assert is_hold_active(txn) is False


def test_is_hold_active_false_for_terminal_status() -> None:
    txn = Transaction(
        listing_id="l1",
        payer_id="p1",
        payee_id="p2",
        transaction_type="shortlet_booking",
        gross_amount=100.0,
        commission_amount=0.0,
        net_payout_amount=100.0,
        status="payment_received",
        hold_expires_at=datetime.now(UTC) + timedelta(minutes=5),
    )
    assert is_hold_active(txn) is False


def test_is_hold_active_handles_naive_hold_expires_at() -> None:
    """Regression test: production (real Postgres, not just the SQLite test
    harness) hit "can't compare offset-naive and offset-aware datetimes"
    for the structurally identical comparison in
    listing_service.list_host_listings -- `is_hold_active` has the exact
    same shape of comparison against a DB-sourced `hold_expires_at`, and a
    TypeError here would break the FEAT-032 booking hold check, a P0
    payment-flow path. `hold_expires_at` set naive here (no tzinfo)
    simulates whatever driver/session condition produced a naive datetime
    in production despite the column being `DateTime(timezone=True)`."""
    # Naive-but-actually-UTC (mirrors what a driver stripping tzinfo off an
    # otherwise-correct UTC value would produce) -- NOT `datetime.now()`,
    # which is naive LOCAL time and would make this test's pass/fail
    # depend on the machine's timezone offset from UTC.
    now_naive_utc = datetime.now(UTC).replace(tzinfo=None)
    txn = Transaction(
        listing_id="l1",
        payer_id="p1",
        payee_id="p2",
        transaction_type="shortlet_booking",
        gross_amount=100.0,
        commission_amount=0.0,
        net_payout_amount=100.0,
        status="held",
        hold_expires_at=now_naive_utc + timedelta(minutes=5),
    )
    assert txn.hold_expires_at.tzinfo is None
    assert is_hold_active(txn) is True

    txn.hold_expires_at = now_naive_utc - timedelta(minutes=1)  # naive, expired
    assert is_hold_active(txn) is False
