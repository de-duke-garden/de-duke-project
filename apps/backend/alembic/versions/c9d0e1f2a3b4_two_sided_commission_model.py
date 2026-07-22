"""two-sided commission model: buyer_fee + owner_commission

Revision ID: c9d0e1f2a3b4
Revises: f7a8b9c0d1e2
Create Date: 2026-07-23 00:00:00.000000

Product decision: instead of one commission rate deducted from the
listing price on the payee's side only, there are now two independent,
independently-configurable rates per transaction_type:
  - `buyer_fee` -- a surcharge ADDED to the listing price (what the guest
    pays on top).
  - `owner_commission` -- a percentage DEDUCTED from the listing price
    (what the payee's net payout is reduced by).

Two things happen here:
  1. `commission_rate_configs` gets a new `fee_type` column ('buyer_fee' |
     'owner_commission'), discriminating two independent append-only rate
     histories per transaction_type instead of one. Every existing row
     predates this split and represented a deduction from the payee's
     payout with no separate buyer-side fee -- backfilled to
     'owner_commission', the closest semantic match, then the column is
     made non-nullable.
  2. `transactions` gets three new nullable columns --
     `listing_price`/`buyer_fee_amount`/`owner_commission_amount` -- for
     the full breakdown. Backfilled for existing rows from the old
     single-rate model's own values: `listing_price = gross_amount`
     (the old model charged exactly the listing price, no buyer fee),
     `buyer_fee_amount = 0`, `owner_commission_amount = commission_amount`
     (the old model's commission was entirely a payee-side deduction).
     This preserves both invariants
     (`gross_amount = listing_price + buyer_fee_amount`,
     `net_payout_amount = listing_price - owner_commission_amount`) for
     every historical row, not just new ones.
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "c9d0e1f2a3b4"
down_revision: str | None = "f7a8b9c0d1e2"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # -- 1. CommissionRateConfig.fee_type -------------------------------
    op.add_column(
        "commission_rate_configs",
        sa.Column("fee_type", sa.String(), nullable=True),
    )
    rate_configs = sa.table("commission_rate_configs", sa.column("fee_type", sa.String))
    op.execute(rate_configs.update().values(fee_type="owner_commission"))
    op.alter_column("commission_rate_configs", "fee_type", nullable=False)
    op.create_index(
        "ix_commission_rate_configs_fee_type", "commission_rate_configs", ["fee_type"]
    )

    # -- 2. Transaction price breakdown columns -------------------------
    op.add_column("transactions", sa.Column("listing_price", sa.Float(), nullable=True))
    op.add_column("transactions", sa.Column("buyer_fee_amount", sa.Float(), nullable=True))
    op.add_column("transactions", sa.Column("owner_commission_amount", sa.Float(), nullable=True))

    transactions = sa.table(
        "transactions",
        sa.column("listing_price", sa.Float),
        sa.column("buyer_fee_amount", sa.Float),
        sa.column("owner_commission_amount", sa.Float),
        sa.column("gross_amount", sa.Float),
        sa.column("commission_amount", sa.Float),
    )
    op.execute(
        transactions.update().values(
            listing_price=transactions.c.gross_amount,
            buyer_fee_amount=0.0,
            owner_commission_amount=transactions.c.commission_amount,
        )
    )


def downgrade() -> None:
    op.drop_column("transactions", "owner_commission_amount")
    op.drop_column("transactions", "buyer_fee_amount")
    op.drop_column("transactions", "listing_price")

    op.drop_index("ix_commission_rate_configs_fee_type", table_name="commission_rate_configs")
    # Deliberately NOT reversing the fee_type backfill's absence-of-data --
    # there's nothing to reverse (the column itself is dropped), but same
    # reasoning as this codebase's other backfill migrations: a downgrade
    # never attempts to resurrect a distinction (buyer_fee vs
    # owner_commission history) that didn't exist before this migration ran.
    op.drop_column("commission_rate_configs", "fee_type")
