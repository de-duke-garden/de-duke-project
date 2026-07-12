#!/usr/bin/env python
"""Synthetic data seeder for the load-test suite (load_tests/README.md's
Target Scale table) -- generates data at millions-scale volume since
"query planner behavior, cache hit ratios, and index performance at small
data volumes are not representative of behavior at scale" (architecture.md,
Load Testing & Performance Validation, Environment & Data Volume).

Lives in apps/backend/scripts/ (not load_tests/) and reuses
app.core.db.async_session_factory -- i.e. the SAME database_url the running
backend service assembles for itself from DB_PROXY_ENDPOINT/DB_CREDENTIALS
(app/core/config.py's _apply_deployed_secrets) -- rather than requiring a
separately-supplied plaintext DB URL. This mirrors scripts/bootstrap_admin.py's
existing pattern. It also means this script can ONLY run from inside the
VPC (as a one-off ECS Fargate task, same as backend-deploy.yml's "Run
database migrations" step) -- GitHub-hosted Actions runners have no network
path to the private-subnet RDS Proxy, so this is never invoked directly
from a runner. See .github/workflows/load-test-full.yml's `seed` job.

Uses SQLModel ORM objects (session.add / session.add_all), not raw SQL --
deliberately, after an earlier raw-SQL version repeatedly hit
NotNullViolationError against columns (created_at, updated_at,
location_latitude/longitude, host_photo_url, bio, ...) that only have
Python-side `default_factory` defaults, not database-level ones. Going
through the ORM applies every model default automatically and structurally
prevents this whole class of bug, matching the pattern
app/services/listing_service.py's create_listing and
scripts/bootstrap_admin.py already use for real writes.

Usage (invoked via `aws ecs run-task` with an overridden container command,
never run manually against a real environment without the same care given
to bootstrap_admin.py):

    python scripts/seed_load_test_data.py --listings 5000000 --users 2000000 --transactions 500000

Safety: refuses to run unless DB_PROXY_ENDPOINT (the env var ECS injects,
see app/core/config.py) starts with "staging-" -- there is no legitimate
reason for this script to ever touch development or production.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import delete, select  # noqa: E402

from app.core.db import async_session_factory  # noqa: E402
from app.core.security import hash_password  # noqa: E402
from app.models.host_account import HostAccount  # noqa: E402
from app.models.listing import Listing  # noqa: E402
from app.models.transaction import Transaction  # noqa: E402
from app.models.user import User  # noqa: E402
from app.services.listing_service import make_location_point_wkt  # noqa: E402

SYNTHETIC_PASSWORD = "LoadTest-Synthetic-Only-1!"  # matches load_tests/lib/client.js's loginSyntheticUser
BATCH_SIZE = 2000

# This task has no writable, retrievable filesystem from the outside (it's
# a one-off Fargate task -- nothing mounts its /tmp, and it's gone the
# moment it exits) and no network path back to the GitHub Actions runner
# that launched it. The only channel this task's stdout reaches the
# outside world through is CloudWatch Logs, which
# .github/workflows/load-test-full.yml's `seed` job reads back afterward
# via `aws logs get-log-events` and greps for this marker prefix to
# reconstruct load_tests/seed/*.json for the k6 scenario scripts. Keep each
# marker line as a SINGLE line of compact JSON (no pretty-printing) so it
# survives log-line splitting intact.
SEED_OUTPUT_MARKER = "SEED_OUTPUT_JSON::"


def _require_staging_environment() -> None:
    """DB_PROXY_ENDPOINT is set by infra/modules/fargate_service's
    container definition to the RDS Proxy's own endpoint, which always
    starts with "<environment>-de-duke-..." (see modules/rds_postgres's
    proxy naming) -- checking its prefix is a reliable, ECS-native way to
    confirm which environment this task is actually running in, without
    needing a separately-threaded --environment flag that could drift from
    the task's real placement.
    """
    db_proxy_endpoint = os.environ.get("DB_PROXY_ENDPOINT", "")
    if not db_proxy_endpoint.startswith("staging-"):
        print(
            f"Refusing to run: DB_PROXY_ENDPOINT ({db_proxy_endpoint!r}) does not "
            "look like staging's RDS Proxy. This seeder only ever runs "
            "against staging -- see load_tests/README.md.",
            file=sys.stderr,
        )
        sys.exit(2)


async def truncate_synthetic_data(session) -> None:
    """Deletes only previously-seeded synthetic rows (identified by the
    `@synthetic.de-duke.internal` email suffix), never real staging data
    that might exist from manual QA -- staging is shared with other
    pre-launch testing, not exclusively owned by this seeder.

    Must delete in FK dependency order (transactions -> listings ->
    host_accounts -> users) -- confirmed via a real staging run:
    host_accounts.user_id has no ON DELETE CASCADE (see
    app/models/host_account.py), so a bare `DELETE FROM users` on a second
    run (after a first run had already created host_accounts) fails with
    ForeignKeyViolationError. There is no ORM-level cascade configured
    either, so this can't be simplified to a single `session.delete(user)`
    per user and letting SQLAlchemy cascade it.
    """
    synthetic_user_ids = (
        (
            await session.execute(
                select(User.id).where(User.email.like("%@synthetic.de-duke.internal"))
            )
        )
        .scalars()
        .all()
    )
    if not synthetic_user_ids:
        return

    synthetic_host_account_ids = (
        (
            await session.execute(
                select(HostAccount.id).where(HostAccount.user_id.in_(synthetic_user_ids))
            )
        )
        .scalars()
        .all()
    )
    synthetic_listing_ids = (
        (
            await session.execute(
                select(Listing.id).where(Listing.host_account_id.in_(synthetic_host_account_ids))
            )
        )
        .scalars()
        .all()
    )

    await session.execute(
        delete(Transaction).where(
            Transaction.listing_id.in_(synthetic_listing_ids)
            | Transaction.payer_id.in_(synthetic_user_ids)
        )
    )
    await session.execute(delete(Listing).where(Listing.id.in_(synthetic_listing_ids)))
    await session.execute(
        delete(HostAccount).where(HostAccount.id.in_(synthetic_host_account_ids))
    )
    await session.execute(delete(User).where(User.id.in_(synthetic_user_ids)))


async def seed_users(session, count: int) -> list[str]:
    user_ids: list[str] = []
    for batch_start in range(0, count, BATCH_SIZE):
        batch = []
        for i in range(batch_start, min(batch_start + BATCH_SIZE, count)):
            user = User(
                email=f"load+{i}@synthetic.de-duke.internal",
                full_name=f"Load Test User {i}",
                role="seeker",
                password_hash=hash_password(SYNTHETIC_PASSWORD),
                is_active=True,
            )
            batch.append(user)
        session.add_all(batch)
        await session.flush()
        user_ids.extend(u.id for u in batch)
        print(f"  seeded users {batch_start}-{batch_start + len(batch)}/{count}")
    return user_ids


async def seed_verified_hosts(session, count: int) -> list[str]:
    """Verified HostAccounts -- listing_creation.js's listing creation
    requires one (see app/api/v1/listings.py's _get_own_host_account)."""
    host_account_ids: list[str] = []
    for i in range(count):
        user = User(
            # Bug found via a real staging run: this used to share seed_users'
            # `load+{i}@...` numbering space, which collides on email's
            # unique index the moment both functions seed index 0 --
            # verified hosts get their own `load+host{i}@...` namespace
            # instead. See lib/client.js's loginSyntheticHost, which must
            # use this same prefix.
            email=f"load+host{i}@synthetic.de-duke.internal",
            full_name=f"Load Test Host {i}",
            role="host",
            password_hash=hash_password(SYNTHETIC_PASSWORD),
            is_active=True,
            is_verified_host=True,
        )
        session.add(user)
        await session.flush()  # assign user.id

        host_account = HostAccount(
            user_id=user.id,
            host_type="owner",
            host_photo_url="https://example.com/synthetic/load-test-host.jpg",
            bio="Synthetic load-test host account, safe to purge.",
            status="verified",
        )
        session.add(host_account)
        await session.flush()  # assign host_account.id
        host_account_ids.append(host_account.id)
    print(f"  seeded {count} verified host accounts")
    return host_account_ids


def _synthetic_listing(i: int, host_account_id: str, *, title: str) -> Listing:
    lat = 4 + (i % 900) / 100.0  # spread across Nigeria's rough bounding box
    lng = 3 + (i % 1100) / 100.0
    return Listing(
        host_account_id=host_account_id,
        listing_type="shortlet" if i % 2 == 0 else "commercial",
        title=title,
        description="Synthetic load-test listing, safe to purge.",
        location_latitude=lat,
        location_longitude=lng,
        location_address_line=f"{i} Load Test Close",
        location_city="Lagos",
        location_state="Lagos",
        location_point=make_location_point_wkt(lat, lng),
        amenities=["wifi", "generator"],
        status="active",
    )


async def seed_listings(session, count: int, host_account_ids: list[str]) -> list[str]:
    listing_ids: list[str] = []
    for batch_start in range(0, count, BATCH_SIZE):
        batch = []
        for i in range(batch_start, min(batch_start + BATCH_SIZE, count)):
            host_account_id = host_account_ids[i % len(host_account_ids)]
            batch.append(_synthetic_listing(i, host_account_id, title=f"Load Test Listing {i}"))
        session.add_all(batch)
        await session.flush()
        listing_ids.extend(listing.id for listing in batch)
        print(f"  seeded listings {batch_start}-{batch_start + len(batch)}/{count}")
    return listing_ids


async def seed_contended_listings(session, host_account_ids: list[str], count: int = 20) -> list[str]:
    """A small pool of listings deliberately reused by
    booking_hold_contention.js so many concurrent VUs race for the SAME
    slot -- distinct from the bulk `listings` pool above, which is spread
    out to avoid contention (that's search_discovery.js's job)."""
    batch = [
        _synthetic_listing(
            i, host_account_ids[i % len(host_account_ids)], title=f"Load Test Contended Listing {i}"
        )
        for i in range(count)
    ]
    session.add_all(batch)
    await session.flush()
    return [listing.id for listing in batch]


async def seed_viral_listing(session, host_account_ids: list[str]) -> str:
    listing = _synthetic_listing(0, host_account_ids[0], title="Load Test Viral Listing")
    session.add(listing)
    await session.flush()
    return listing.id


async def seed_checkout_transactions(
    session, user_ids: list[str], listing_ids: list[str], count: int
) -> list[str]:
    """`held` Transactions ready for checkout_payment.js to drive through
    /checkout/initiate + /checkout/webhook."""
    transaction_ids: list[str] = []
    for batch_start in range(0, count, BATCH_SIZE):
        batch = []
        for i in range(batch_start, min(batch_start + BATCH_SIZE, count)):
            batch.append(
                Transaction(
                    listing_id=listing_ids[i % len(listing_ids)],
                    payer_id=user_ids[i % len(user_ids)],
                    payee_id=user_ids[(i + 1) % len(user_ids)],
                    transaction_type="shortlet_booking",
                    gross_amount=100000.0,
                    commission_amount=10000.0,
                    net_payout_amount=90000.0,
                    status="held",
                )
            )
        session.add_all(batch)
        await session.flush()
        transaction_ids.extend(t.id for t in batch)
        print(f"  seeded checkout transactions {batch_start}-{batch_start + len(batch)}/{count}")
    return transaction_ids


def _emit_json(filename: str, data) -> None:
    """Prints a single-line marker the CI workflow greps out of CloudWatch
    Logs afterward -- see SEED_OUTPUT_MARKER's comment above for why this
    is the only viable channel out of a one-off Fargate task."""
    payload = json.dumps({"filename": filename, "data": data}, separators=(",", ":"))
    print(f"{SEED_OUTPUT_MARKER}{payload}")


async def run(args: argparse.Namespace) -> None:
    async with async_session_factory() as session:
        print("Truncating previously-seeded synthetic data...")
        await truncate_synthetic_data(session)
        await session.commit()

        print(f"Seeding {args.verified_hosts} verified hosts...")
        host_account_ids = await seed_verified_hosts(session, args.verified_hosts)
        await session.commit()

        print(f"Seeding {args.users} users...")
        user_ids = await seed_users(session, args.users)
        await session.commit()

        print(f"Seeding {args.listings} listings...")
        listing_ids = await seed_listings(session, args.listings, host_account_ids)
        await session.commit()

        print("Seeding contended listings for booking_hold_contention.js...")
        contended_ids = await seed_contended_listings(session, host_account_ids)
        await session.commit()
        _emit_json("contended_listing_ids.json", contended_ids)

        print("Seeding viral listing for spike.js...")
        viral_id = await seed_viral_listing(session, host_account_ids)
        await session.commit()
        _emit_json("viral_listing_id.json", {"id": viral_id})

        print(f"Seeding {args.transactions} checkout transactions...")
        checkout_ids = await seed_checkout_transactions(
            session, user_ids, listing_ids, args.transactions
        )
        await session.commit()
        # k6 doesn't need the full multi-hundred-thousand set in memory.
        _emit_json("checkout_transaction_ids.json", checkout_ids[:10000])

    print("Seeding complete. Seed output JSON emitted above via SEED_OUTPUT_JSON:: markers.")


def main() -> None:
    _require_staging_environment()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--users", type=int, default=2_000_000)
    parser.add_argument("--listings", type=int, default=5_000_000)
    parser.add_argument("--transactions", type=int, default=500_000)
    parser.add_argument("--verified-hosts", type=int, default=5_000)
    args = parser.parse_args()
    asyncio.run(run(args))


if __name__ == "__main__":
    main()
