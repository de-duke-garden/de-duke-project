"""Unit tests for FEAT-014 two-sided commission math -- pure functions, no
DB needed."""

from app.services.commission_service import DEFAULT_RATE_PERCENTAGE, compute_price_breakdown


def test_compute_price_breakdown_basic() -> None:
    breakdown = compute_price_breakdown(100_000.0, 2.0, 4.0)
    assert breakdown.listing_price == 100_000.0
    assert breakdown.buyer_fee_amount == 2_000.0
    assert breakdown.owner_commission_amount == 4_000.0
    assert breakdown.gross_amount == 102_000.0
    assert breakdown.net_payout_amount == 96_000.0
    assert breakdown.commission_amount == 6_000.0
    # Invariant every existing caller relies on: commission_amount is
    # always exactly gross_amount - net_payout_amount, regardless of how
    # it's split between the two fee components.
    assert breakdown.commission_amount == round(
        breakdown.gross_amount - breakdown.net_payout_amount, 2
    )


def test_compute_price_breakdown_zero_rates() -> None:
    breakdown = compute_price_breakdown(50_000.0, 0.0, 0.0)
    assert breakdown.buyer_fee_amount == 0.0
    assert breakdown.owner_commission_amount == 0.0
    assert breakdown.gross_amount == 50_000.0
    assert breakdown.net_payout_amount == 50_000.0
    assert breakdown.commission_amount == 0.0


def test_compute_price_breakdown_rounds_to_cents() -> None:
    breakdown = compute_price_breakdown(99.99, 2.5, 7.5)
    assert breakdown.buyer_fee_amount == round(99.99 * 0.025, 2)
    assert breakdown.owner_commission_amount == round(99.99 * 0.075, 2)
    assert round(breakdown.gross_amount - breakdown.listing_price, 2) == breakdown.buyer_fee_amount
    assert (
        round(breakdown.listing_price - breakdown.net_payout_amount, 2)
        == breakdown.owner_commission_amount
    )


def test_default_rates_are_reasonable_fallbacks() -> None:
    assert 0 <= DEFAULT_RATE_PERCENTAGE["buyer_fee"] <= 100
    assert 0 <= DEFAULT_RATE_PERCENTAGE["owner_commission"] <= 100
    # Product decision: 2% buyer-side fee, 4% owner-side commission.
    assert DEFAULT_RATE_PERCENTAGE["buyer_fee"] == 2.0
    assert DEFAULT_RATE_PERCENTAGE["owner_commission"] == 4.0
