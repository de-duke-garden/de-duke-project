"""add user email notification preferences

Revision ID: efa2c5614458
Revises: 231e83887366
Create Date: 2026-07-07 21:02:01.878028

Hand-edited: autogenerate against the local dev docker-compose stack's
Postgres also picked up ~40 unrelated "drop table"/"create table"
statements for tables belonging to the postgis extension's bundled Tiger
geocoder schema (place_lookup, tabblock, faces, edges, etc.) and a demo
table (exemplo_dados) baked into that image -- none of these are part of
SQLModel.metadata or this project's schema at all, and must never be
touched by an application migration. Stripped down to the one real change:
adding User.email_notification_preferences (FEAT-024 AC).
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "efa2c5614458"
down_revision: str | None = "231e83887366"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("users", sa.Column("email_notification_preferences", sa.JSON(), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "email_notification_preferences")
