"""FEAT-014 (Automatic Commission Deduction) + FEAT-027 (Commission Rate
Configuration) business logic.

Two-sided commission model (product decision): a `buyer_fee` percentage is
added ON TOP of the listing price (what the guest actually pays), and a
separate `owner_commission` percentage is deducted FROM the listing price
(what the payee's net payout is reduced by). These are two independent,
independently-configurable rates -- NOT one rate split two ways -- each
with its own append-only effective_from history per transaction_type
(CommissionRateConfig.fee_type discriminates them; see that model's own
docstring).

Rate history: `CommissionRateConfig` rows are append-only (a new row per
change, per schema.md's `effective_from`) -- never mutate an existing row.
A change is only effective for transactions initiated after the change,
so commission calculation always looks up the config row with the latest
`effective_from <= as_of` for the transaction's (type, fee_type) pair, and
the resulting rates are snapshotted onto the Transaction at hold-creation
time (`listing_price`/`buyer_fee_amount`/`owner_commission_amount`/
`gross_amount`/`net_payout_amount`/`commission_amount`) rather than
recomputed later -- the charge amount itself (gross_amount) must already
include the buyer fee before checkout can initiate the Paystack
transaction, so this can no longer be deferred to payment-webhook time
the way the old single-rate model was.
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.ops import CommissionRateConfig

FEE_TYPES = ("buyer_fee", "owner_commission")

# Fallback only if an Admin has never configured a rate for this
# (transaction_type, fee_type) pair. These are the current product
# defaults (2% buyer-side fee, 4% owner-side commission) -- both remain
# fully overridable per transaction_type via Commission Config; this is
# just what applies until/unless an Admin sets an explicit rate.
DEFAULT_RATE_PERCENTAGE = {
    "buyer_fee": 2.0,
    "owner_commission": 4.0,
}


async def get_effective_rate(
    session: AsyncSession, transaction_type: str, fee_type: str, as_of: datetime | None = None
) -> float:
    as_of = as_of or datetime.now(UTC)
    result = await session.execute(
        select(CommissionRateConfig)
        .where(CommissionRateConfig.transaction_type == transaction_type)
        .where(CommissionRateConfig.fee_type == fee_type)
        .where(CommissionRateConfig.effective_from <= as_of)
        .order_by(CommissionRateConfig.effective_from.desc())
        .limit(1)
    )
    config = result.scalar_one_or_none()
    return config.rate_percentage if config is not None else DEFAULT_RATE_PERCENTAGE[fee_type]


async def get_effective_rates(
    session: AsyncSession, transaction_type: str, as_of: datetime | None = None
) -> tuple[float, float]:
    """Convenience wrapper -- returns (buyer_fee_percentage,
    owner_commission_percentage) for a transaction_type as of the same
    instant, since every real call site (booking_service.confirm_booking)
    needs both rates together to compute a full price breakdown."""
    buyer_fee_pct = await get_effective_rate(session, transaction_type, "buyer_fee", as_of=as_of)
    owner_commission_pct = await get_effective_rate(
        session, transaction_type, "owner_commission", as_of=as_of
    )
    return buyer_fee_pct, owner_commission_pct


class PriceBreakdown:
    """Full two-sided commission breakdown for one transaction. Not a
    Pydantic schema (that's app/schemas/transaction.py's job) -- just the
    computed values booking_service.confirm_booking assigns directly onto
    a new Transaction row."""

    __slots__ = (
        "listing_price",
        "buyer_fee_amount",
        "owner_commission_amount",
        "gross_amount",
        "net_payout_amount",
        "commission_amount",
    )

    def __init__(
        self,
        *,
        listing_price: float,
        buyer_fee_amount: float,
        owner_commission_amount: float,
        gross_amount: float,
        net_payout_amount: float,
        commission_amount: float,
    ) -> None:
        self.listing_price = listing_price
        self.buyer_fee_amount = buyer_fee_amount
        self.owner_commission_amount = owner_commission_amount
        self.gross_amount = gross_amount
        self.net_payout_amount = net_payout_amount
        self.commission_amount = commission_amount


def compute_price_breakdown(
    listing_price: float, buyer_fee_percentage: float, owner_commission_percentage: float
) -> PriceBreakdown:
    """The two-sided commission math (product decision):
      - gross_amount (charged to guest) = listing_price + buyer_fee_amount
      - net_payout_amount (paid to payee) = listing_price - owner_commission_amount
      - commission_amount (total De-Duke revenue) = buyer_fee_amount + owner_commission_amount
        (always exactly gross_amount - net_payout_amount -- see
        Transaction.commission_amount's own docstring for why that
        identity matters to existing callers).
    """
    buyer_fee_amount = round(listing_price * (buyer_fee_percentage / 100.0), 2)
    owner_commission_amount = round(listing_price * (owner_commission_percentage / 100.0), 2)
    gross_amount = round(listing_price + buyer_fee_amount, 2)
    net_payout_amount = round(listing_price - owner_commission_amount, 2)
    commission_amount = round(buyer_fee_amount + owner_commission_amount, 2)
    return PriceBreakdown(
        listing_price=listing_price,
        buyer_fee_amount=buyer_fee_amount,
        owner_commission_amount=owner_commission_amount,
        gross_amount=gross_amount,
        net_payout_amount=net_payout_amount,
        commission_amount=commission_amount,
    )


async def set_commission_rate(
    session: AsyncSession,
    *,
    transaction_type: str,
    fee_type: str,
    rate_percentage: float,
    set_by_id: str,
) -> CommissionRateConfig:
    if fee_type not in FEE_TYPES:
        raise ValueError(f"fee_type must be one of {FEE_TYPES}")
    if not 0 <= rate_percentage <= 100:
        raise ValueError("rate_percentage must be between 0 and 100")
    config = CommissionRateConfig(
        transaction_type=transaction_type,
        fee_type=fee_type,
        rate_percentage=rate_percentage,
        set_by_id=set_by_id,
        effective_from=datetime.now(UTC),
    )
    session.add(config)
    await session.flush()
    return config


async def get_rate_history(
    session: AsyncSession, transaction_type: str, fee_type: str
) -> list[CommissionRateConfig]:
    result = await session.execute(
        select(CommissionRateConfig)
        .where(CommissionRateConfig.transaction_type == transaction_type)
        .where(CommissionRateConfig.fee_type == fee_type)
        .order_by(CommissionRateConfig.effective_from.desc())
    )
    return list(result.scalars().all())
