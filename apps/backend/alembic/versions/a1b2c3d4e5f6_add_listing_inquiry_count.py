"""add listing inquiry_count

Revision ID: a1b2c3d4e5f6
Revises: efa2c5614458
Create Date: 2026-07-12 01:00:00.000000

FEAT-017 (Host Dashboard) AC: listing cards show "basic metrics (views,
inquiries)". Denormalized counter, same pattern as the pre-existing
(if previously never-incremented) listings.view_count column -- see
app/models/listing.py's inquiry_count comment.
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "a1b2c3d4e5f6"
down_revision: str | None = "efa2c5614458"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "listings",
        sa.Column("inquiry_count", sa.Integer(), nullable=False, server_default="0"),
    )


def downgrade() -> None:
    op.drop_column("listings", "inquiry_count")
