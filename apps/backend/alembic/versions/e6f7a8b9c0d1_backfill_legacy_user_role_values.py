"""backfill legacy user role values (seeker/individual_host/corporate)

Revision ID: e6f7a8b9c0d1
Revises: d3e4f5a6b7c8
Create Date: 2026-07-22 00:00:00.000000

Bug fix, found while manually verifying FEAT-001/FEAT-003 acceptance
criteria against a live local dev environment: `POST /v1/auth/firebase-
exchange` (and `/login`, `/refresh`, `/me/role`) 500s with
`ValueError: '<value>' is not a valid UserRole` for any `User` row whose
`role` column still holds a *pre-rename* value.

`app/core/security.py`'s `UserRole` enum was renamed from
`SEEKER / INDIVIDUAL_HOST / AGENCY / CORPORATE / DEDUKE_STAFF /
DEDUKE_ADMIN` to `GUEST / HOST / AGENCY / DEDUKE_STAFF / DEDUKE_ADMIN`
in commit ae0b9a3 (FEAT-001's Google/Firebase sign-in rewrite), but that
change only touched application code -- no Alembic migration ever
backfilled the existing `users.role` column values to match, violating
architecture.md's own "expand-contract" migration pattern (the "contract"
half -- retiring the old shape -- was never actually paired with a data
migration). `b1c2d3e4f5a6` (the migration that shipped alongside the same
commit) backfills `auth_provider` only; its own docstring flags "a handful
may in practice be pre-Firebase seeker/host accounts" without addressing
it, which is exactly the gap this migration closes.

Confirmed via direct query against the local dev DB: real rows (including
at least one live Firebase-linked user, not just seed/test data) were
still carrying `seeker`/`individual_host`, each one permanently 500ing on
every authenticated request from that point on (`create_access_token`
calls `UserRole(user.role)` with no fallback).

Mapping (1:1, matches the pre-rename -> post-rename enum correspondence):
  seeker          -> guest   (FEAT-003's default self-service role)
  individual_host -> host
  corporate       -> agency  (CORPORATE was dropped outright in the
                     rename, not renamed to anything specific; `agency`
                     is the closest surviving self-service role and the
                     one CORPORATE-type accounts would map to under the
                     current three-role model -- FEAT-003's Role
                     Selection screen only ever offers Guest/Host/Agency)

`agency`/`deduke_staff`/`deduke_admin` rows are already correct and
untouched. No corporate rows exist in the local dev DB at the time of
writing, but the backfill is included anyway since this same gap could be
present in any other environment (staging/production) that carried data
through the same rename.
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "e6f7a8b9c0d1"
down_revision: str | None = "d3e4f5a6b7c8"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_RENAMES = {
    "seeker": "guest",
    "individual_host": "host",
    "corporate": "agency",
}


def upgrade() -> None:
    users = sa.table("users", sa.column("role", sa.String))
    for old_value, new_value in _RENAMES.items():
        op.execute(
            users.update().where(users.c.role == old_value).values(role=new_value)
        )


def downgrade() -> None:
    # Deliberately a no-op, not a reverse-rename: by the time this
    # migration has run, there is no way to tell a row that was
    # genuinely created as 'guest'/'host' post-rename apart from one that
    # was backfilled from 'seeker'/'individual_host' by upgrade() above --
    # reversing it would incorrectly rename legitimate new rows back to
    # the retired values. The application code's UserRole enum (already
    # renamed in ae0b9a3, well before this migration) doesn't recognize
    # the old values either way, so downgrading this migration alone
    # without also reverting that code change would immediately
    # reintroduce the exact bug this migration fixes.
    pass
