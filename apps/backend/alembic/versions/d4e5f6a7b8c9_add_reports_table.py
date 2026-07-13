"""add reports table (FEAT-009)

Revision ID: d4e5f6a7b8c9
Revises: c3d4e5f6a7b8
Create Date: 2026-07-13 00:00:00.000001

New standalone table backing app/models/report.py's `Report` model --
seeker-raised reports against a Listing or a Firestore-hosted chat
conversation (target_id is only a real FK-shaped Postgres id when
target_type == "listing"; never enforced as a DB foreign key here since
conversations aren't Primary Database rows -- see report.py's docstring).

Expand-only: a brand new table, so this migration cannot affect existing
rows/behavior. Safe to apply ahead of a deploy that starts writing to it.
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "d4e5f6a7b8c9"
down_revision: str | None = "c3d4e5f6a7b8"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "reports",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("reporter_user_id", sa.String(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("target_type", sa.String(), nullable=False),
        sa.Column("target_id", sa.String(), nullable=False),
        sa.Column("reason", sa.String(), nullable=False),
        sa.Column("detail", sa.String(), nullable=True),
        sa.Column("status", sa.String(), nullable=False, server_default="open"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("resolved_by_user_id", sa.String(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("resolution_note", sa.String(), nullable=True),
    )
    op.create_index("ix_reports_reporter_user_id", "reports", ["reporter_user_id"])
    op.create_index("ix_reports_target_type", "reports", ["target_type"])
    op.create_index("ix_reports_target_id", "reports", ["target_id"])
    op.create_index("ix_reports_status", "reports", ["status"])


def downgrade() -> None:
    op.drop_index("ix_reports_status", table_name="reports")
    op.drop_index("ix_reports_target_id", table_name="reports")
    op.drop_index("ix_reports_target_type", table_name="reports")
    op.drop_index("ix_reports_reporter_user_id", table_name="reports")
    op.drop_table("reports")
