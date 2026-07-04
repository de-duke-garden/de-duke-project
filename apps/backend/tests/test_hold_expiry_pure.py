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
        status="succeeded",
        hold_expires_at=datetime.now(UTC) + timedelta(minutes=5),
    )
    assert is_hold_active(txn) is False
