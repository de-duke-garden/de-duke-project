"""add saved_search_alert_logs table (FEAT-023)

Revision ID: e5f6a7b8c9d0
Revises: d4e5f6a7b8c9
Create Date: 2026-07-13 00:00:00.000002

New standalone table backing app/models/saved_search_alert.py's
`SavedSearchAlertLog` model -- the double-notification guard for
app/workers/saved_search_alert_job.py's periodic sweep. One row per
(saved_search, listing) pair that has already triggered a push
notification; the unique constraint is the actual dedupe mechanism.

Expand-only: a brand new table, no existing rows/behavior affected.
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "e5f6a7b8c9d0"
down_revision: str | None = "d4e5f6a7b8c9"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "saved_search_alert_logs",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column(
            "saved_search_id",
            sa.String(),
            sa.ForeignKey("saved_searches.id"),
            nullable=False,
        ),
        sa.Column("listing_id", sa.String(), sa.ForeignKey("listings.id"), nullable=False),
        sa.Column("notified_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint("saved_search_id", "listing_id", name="uq_saved_search_alert_pair"),
    )
    op.create_index(
        "ix_saved_search_alert_logs_saved_search_id",
        "saved_search_alert_logs",
        ["saved_search_id"],
    )
    op.create_index(
        "ix_saved_search_alert_logs_listing_id", "saved_search_alert_logs", ["listing_id"]
    )


def downgrade() -> None:
    op.drop_index("ix_saved_search_alert_logs_listing_id", table_name="saved_search_alert_logs")
    op.drop_index(
        "ix_saved_search_alert_logs_saved_search_id", table_name="saved_search_alert_logs"
    )
    op.drop_table("saved_search_alert_logs")
