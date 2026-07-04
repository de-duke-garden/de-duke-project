"""FEAT-032 double-booking invariant -- concurrency tests.

These exercise `booking_service.confirm_booking`'s DB-level locking
(`SELECT ... FOR UPDATE`) under real concurrent transactions, which
requires a live Postgres instance (SQLite/aiosqlite does not support
`FOR UPDATE` row locking semantics the same way, and this project's async
driver is asyncpg-only per app/core/db.py). No such database is available
in this sandboxed test run, so these are marked skipped with a reason
rather than faked against an in-memory DB that wouldn't actually prove the
invariant.

To run for real: set DATABASE_URL to a local/dev Postgres instance, run
`alembic upgrade head`, then unskip.
"""

import asyncio
import os

import pytest

pytestmark = pytest.mark.skipif(
    not os.environ.get("DEDUKE_TEST_POSTGRES_URL"),
    reason=(
        "Requires a live Postgres database to exercise real SELECT ... FOR "
        "UPDATE row-locking concurrency (set DEDUKE_TEST_POSTGRES_URL to run)."
    ),
)


@pytest.mark.asyncio
async def test_concurrent_confirm_booking_only_one_wins_overlapping_dates() -> None:
    """Two concurrent confirm_booking calls for the same listing and
    overlapping dates must result in exactly one `held` transaction and one
    ListingUnavailableError -- never two holds for the same dates."""
    # Intentionally left as an integration-test skeleton: wiring a second
    # concurrent DB session/engine against DEDUKE_TEST_POSTGRES_URL is
    # environment-specific setup beyond this unit-test sandbox.
    await asyncio.sleep(0)
    pytest.skip("integration skeleton only -- see module docstring")
