"""FEAT-014 (Automatic Commission Deduction) + FEAT-027 (Commission Rate
Configuration) business logic.

Rate history: `CommissionRateConfig` rows are append-only (a new row per
change, per schema.md's `effective_from`) -- never mutate an existing row.
A change is only effective for transactions *initiated after* the change,
so commission calculation always looks up the config row with the latest
`effective_from <= as_of` for the transaction's type, and the resulting
`rate_percentage` is snapshotted onto the Transaction at initiation time
(via `commission_amount`/`net_payout_amount`) rather than recomputed later.
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.ops import CommissionRateConfig

DEFAULT_RATE_PERCENTAGE = 10.0  # fallback only if Admin has never configured a rate


async def get_effective_rate(
    session: AsyncSession, transaction_type: str, as_of: datetime | None = None
) -> float:
    as_of = as_of or datetime.now(UTC)
    result = await session.execute(
        select(CommissionRateConfig)
        .where(CommissionRateConfig.transaction_type == transaction_type)
        .where(CommissionRateConfig.effective_from <= as_of)
        .order_by(CommissionRateConfig.effective_from.desc())
        .limit(1)
    )
    config = result.scalar_one_or_none()
    return config.rate_percentage if config is not None else DEFAULT_RATE_PERCENTAGE


def compute_breakdown(gross_amount: float, rate_percentage: float) -> tuple[float, float]:
    """Returns (commission_amount, net_payout_amount)."""
    commission_amount = round(gross_amount * (rate_percentage / 100.0), 2)
    net_payout_amount = round(gross_amount - commission_amount, 2)
    return commission_amount, net_payout_amount


async def set_commission_rate(
    session: AsyncSession,
    *,
    transaction_type: str,
    rate_percentage: float,
    set_by_id: str,
) -> CommissionRateConfig:
    if not 0 <= rate_percentage <= 100:
        raise ValueError("rate_percentage must be between 0 and 100")
    config = CommissionRateConfig(
        transaction_type=transaction_type,
        rate_percentage=rate_percentage,
        set_by_id=set_by_id,
        effective_from=datetime.now(UTC),
    )
    session.add(config)
    await session.flush()
    return config


async def get_rate_history(
    session: AsyncSession, transaction_type: str
) -> list[CommissionRateConfig]:
    result = await session.execute(
        select(CommissionRateConfig)
        .where(CommissionRateConfig.transaction_type == transaction_type)
        .order_by(CommissionRateConfig.effective_from.desc())
    )
    return list(result.scalars().all())
