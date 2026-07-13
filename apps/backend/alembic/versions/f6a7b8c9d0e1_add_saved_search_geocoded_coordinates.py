"""add saved search geocoded coordinates (FEAT-023)

Revision ID: f6a7b8c9d0e1
Revises: e5f6a7b8c9d0
Create Date: 2026-07-13 00:00:00.000003

Adds `location_latitude`/`location_longitude` to `saved_searches`, populated
best-effort at save time by app/services/geocoding_service.py (Google
Geocoding API). Expand-only: both columns are nullable and additive --
existing rows simply have null coordinates until their owner next edits
them (saved_search_service.update_saved_search re-geocodes on any
location_query change), and the matching predicate
(listing_matches_saved_search) already degrades to substring matching
when either is null.
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "f6a7b8c9d0e1"
down_revision: str | None = "e5f6a7b8c9d0"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("saved_searches", sa.Column("location_latitude", sa.Float(), nullable=True))
    op.add_column("saved_searches", sa.Column("location_longitude", sa.Float(), nullable=True))


def downgrade() -> None:
    op.drop_column("saved_searches", "location_longitude")
    op.drop_column("saved_searches", "location_latitude")
