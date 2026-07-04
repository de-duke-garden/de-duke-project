"""Unit tests for FEAT-014 commission math -- pure functions, no DB needed."""

from app.services.commission_service import DEFAULT_RATE_PERCENTAGE, compute_breakdown


def test_compute_breakdown_basic() -> None:
    commission, net = compute_breakdown(100_000.0, 10.0)
    assert commission == 10_000.0
    assert net == 90_000.0


def test_compute_breakdown_zero_rate() -> None:
    commission, net = compute_breakdown(50_000.0, 0.0)
    assert commission == 0.0
    assert net == 50_000.0


def test_compute_breakdown_rounds_to_cents() -> None:
    commission, net = compute_breakdown(99.99, 7.5)
    assert commission == round(99.99 * 0.075, 2)
    assert round(commission + net, 2) == 99.99


def test_default_rate_is_reasonable_fallback() -> None:
    assert 0 <= DEFAULT_RATE_PERCENTAGE <= 100
