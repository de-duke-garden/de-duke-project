"""add wallet/escrow/payout tables (FEAT-043/044/045)

Revision ID: f7a8b9c0d1e2
Revises: e6f7a8b9c0d1
Create Date: 2026-07-22 00:00:00.000000

Product decision (docs/De-Duke/schema.md's Escrow model, shaped via
product-shaper): a successful Paystack charge no longer immediately means
"the host has been paid" -- funds sit in De-Duke's own settlement account
as escrow until a De-Duke Admin manually releases them (FEAT-043) into the
payee's Wallet (FEAT-044), from which the payee can later request an
automated Paystack Transfer withdrawal (FEAT-045).

Two things happen here:
  1. `transactions.status`'s legacy 'succeeded' value is backfilled to
     'payment_received' in place -- a breaking rename, not a new column.
     None are migrated to 'released_to_wallet': no transfer-to-payee
     mechanism existed before this change, so no historical transaction
     can be considered actually released (schema.md's own migration note).
     `transactions.released_at`/`released_by_admin_id` are added, both
     nullable and left NULL for every existing row for the same reason.
  2. Four new tables are created for the wallet/escrow/payout model:
     wallets, wallet_transactions (the immutable ledger `Wallet.balance`
     is derived from -- see schema.md's WalletTransaction docstring on
     why a ledger exists at all, not just a bare balance column),
     payout_settings (bank account details + Paystack recipient), and
     withdrawal_requests (wallet-scoped, deliberately not 1:1 with any
     single Transaction).
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "f7a8b9c0d1e2"
down_revision: str | None = "e6f7a8b9c0d1"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # -- 1. Transaction status rename + new escrow-release columns --------
    op.add_column(
        "transactions",
        sa.Column("released_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "transactions",
        sa.Column("released_by_admin_id", sa.String(), nullable=True),
    )
    op.create_foreign_key(
        "fk_transactions_released_by_admin_id_users",
        "transactions",
        "users",
        ["released_by_admin_id"],
        ["id"],
    )

    transactions = sa.table("transactions", sa.column("status", sa.String))
    op.execute(
        transactions.update()
        .where(transactions.c.status == "succeeded")
        .values(status="payment_received")
    )

    # -- 2. Wallet -----------------------------------------------------------
    op.create_table(
        "wallets",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("owner_id", sa.String(), sa.ForeignKey("users.id"), nullable=False, unique=True),
        sa.Column("balance", sa.Float(), nullable=False, server_default="0"),
        sa.Column("currency", sa.String(), nullable=False, server_default="NGN"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_wallets_owner_id", "wallets", ["owner_id"], unique=True)

    # -- 3. WalletTransaction (ledger) ---------------------------------------
    op.create_table(
        "wallet_transactions",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("wallet_id", sa.String(), sa.ForeignKey("wallets.id"), nullable=False),
        sa.Column("direction", sa.String(), nullable=False),
        sa.Column("amount", sa.Float(), nullable=False),
        sa.Column("source_type", sa.String(), nullable=False),
        sa.Column("source_id", sa.String(), nullable=True),
        sa.Column("balance_after", sa.Float(), nullable=False),
        sa.Column("notes", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_wallet_transactions_wallet_id", "wallet_transactions", ["wallet_id"])
    op.create_index("ix_wallet_transactions_source_type", "wallet_transactions", ["source_type"])
    op.create_index("ix_wallet_transactions_source_id", "wallet_transactions", ["source_id"])

    # -- 4. PayoutSettings -----------------------------------------------
    op.create_table(
        "payout_settings",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("owner_id", sa.String(), sa.ForeignKey("users.id"), nullable=False, unique=True),
        sa.Column("account_number", sa.String(), nullable=False),
        sa.Column("bank_code", sa.String(), nullable=False),
        sa.Column("bank_name", sa.String(), nullable=False),
        sa.Column("account_holder_name", sa.String(), nullable=False),
        sa.Column("verification_status", sa.String(), nullable=False, server_default="unverified"),
        sa.Column("paystack_recipient_code", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_payout_settings_owner_id", "payout_settings", ["owner_id"], unique=True)
    op.create_index(
        "ix_payout_settings_verification_status", "payout_settings", ["verification_status"]
    )

    # -- 5. WithdrawalRequest -------------------------------------------
    op.create_table(
        "withdrawal_requests",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("wallet_id", sa.String(), sa.ForeignKey("wallets.id"), nullable=False),
        sa.Column("amount", sa.Float(), nullable=False),
        sa.Column(
            "payout_settings_id", sa.String(), sa.ForeignKey("payout_settings.id"), nullable=False
        ),
        sa.Column("status", sa.String(), nullable=False, server_default="requested"),
        sa.Column("requested_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("requested_by_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("paystack_transfer_reference", sa.String(), nullable=True),
        sa.Column("fulfilled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("failure_reason", sa.String(), nullable=True),
    )
    op.create_index("ix_withdrawal_requests_wallet_id", "withdrawal_requests", ["wallet_id"])
    op.create_index("ix_withdrawal_requests_status", "withdrawal_requests", ["status"])
    op.create_index(
        "ix_withdrawal_requests_paystack_transfer_reference",
        "withdrawal_requests",
        ["paystack_transfer_reference"],
    )


def downgrade() -> None:
    op.drop_index("ix_withdrawal_requests_paystack_transfer_reference", table_name="withdrawal_requests")
    op.drop_index("ix_withdrawal_requests_status", table_name="withdrawal_requests")
    op.drop_index("ix_withdrawal_requests_wallet_id", table_name="withdrawal_requests")
    op.drop_table("withdrawal_requests")

    op.drop_index("ix_payout_settings_verification_status", table_name="payout_settings")
    op.drop_index("ix_payout_settings_owner_id", table_name="payout_settings")
    op.drop_table("payout_settings")

    op.drop_index("ix_wallet_transactions_source_id", table_name="wallet_transactions")
    op.drop_index("ix_wallet_transactions_source_type", table_name="wallet_transactions")
    op.drop_index("ix_wallet_transactions_wallet_id", table_name="wallet_transactions")
    op.drop_table("wallet_transactions")

    op.drop_index("ix_wallets_owner_id", table_name="wallets")
    op.drop_table("wallets")

    # Deliberately NOT reversing the 'succeeded' -> 'payment_received'
    # backfill -- same reasoning as e6f7a8b9c0d1's own downgrade no-op:
    # by the time this migration has run, there is no way to tell a row
    # that was genuinely written as 'payment_received' post-rename apart
    # from one backfilled here, so reversing would incorrectly rename
    # legitimate new rows back to a value application code (already
    # updated well before this migration would ever be downgraded) no
    # longer recognizes.
    op.drop_constraint(
        "fk_transactions_released_by_admin_id_users", "transactions", type_="foreignkey"
    )
    op.drop_column("transactions", "released_by_admin_id")
    op.drop_column("transactions", "released_at")
