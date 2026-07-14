"""add listing owner_client_name

Revision ID: a7b8c9d0e1f2
Revises: f6a7b8c9d0e1
Create Date: 2026-07-14 09:00:00.000000

FEAT-018 (Agency Portfolio Management) AC: "Each listing can be tagged with
the responsible agent and originating client/owner." The "responsible
agent" half is already derived from Lead/LeadAssignment (see
agency_service.list_agency_listings's docstring); there was no column at
all for "originating client/owner" -- an agency-entered free-text label
(e.g. a landlord's name) distinct from any platform user account, since the
person an agency lists on behalf of usually never signs up themselves.
Nullable/additive: every non-agency listing (the vast majority) simply
never sets it.
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "a7b8c9d0e1f2"
down_revision: str | None = "f6a7b8c9d0e1"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "listings",
        sa.Column("owner_client_name", sa.String(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("listings", "owner_client_name")
