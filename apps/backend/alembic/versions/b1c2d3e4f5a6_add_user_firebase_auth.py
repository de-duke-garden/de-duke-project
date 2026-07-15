"""add user firebase auth fields

Revision ID: b1c2d3e4f5a6
Revises: a7b8c9d0e1f2
Create Date: 2026-07-15 10:00:00.000000

FEAT-001 (Google & Firebase Sign-Up / Login) -- adds User.auth_provider
(discriminates "firebase" vs. the pre-existing backend-managed "password"
flow, now Staff/Admin-only) and User.firebase_uid (resolves an incoming
Firebase ID token to a User record at POST /v1/auth/firebase-exchange).

auth_provider backfills existing rows to 'password' before the column is
made non-nullable -- every row created before this migration was created
through the old backend-managed email/phone+password/OTP flow, so
'password' is the historically correct value for all of them (a handful
may in practice be pre-Firebase seeker/host accounts rather than
Staff/Admin, but there is no way to distinguish that after the fact, and
those rows still authenticate correctly going forward since their
password_hash is untouched -- see auth_service.login_with_email, which
FEAT-001's rewrite left in place for exactly this fallback).
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "b1c2d3e4f5a6"
down_revision: str | None = "a7b8c9d0e1f2"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("auth_provider", sa.String(), nullable=False, server_default="password"),
    )
    op.add_column("users", sa.Column("firebase_uid", sa.String(), nullable=True))
    op.create_index(op.f("ix_users_auth_provider"), "users", ["auth_provider"])
    op.create_index(op.f("ix_users_firebase_uid"), "users", ["firebase_uid"], unique=True)
    # server_default only exists to backfill existing rows during this
    # migration -- new rows always set auth_provider explicitly (User
    # model's Python-side default), same "add NOT NULL column with a
    # server_default, then drop the default" shape as
    # a1b2c3d4e5f6_add_listing_inquiry_count.py.
    op.alter_column("users", "auth_provider", server_default=None)


def downgrade() -> None:
    op.drop_index(op.f("ix_users_firebase_uid"), table_name="users")
    op.drop_index(op.f("ix_users_auth_provider"), table_name="users")
    op.drop_column("users", "firebase_uid")
    op.drop_column("users", "auth_provider")
