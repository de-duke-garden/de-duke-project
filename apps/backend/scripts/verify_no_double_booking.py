#!/usr/bin/env python
"""Authoritative post-run check for Priority Scenario 2 (booking hold
contention) and Scenario 3 (checkout/payment correctness) -- the hard,
non-negotiable pass/fail gate from architecture.md's Load Testing &
Performance Validation section:

    "Zero double-bookings and zero duplicate charges detected across all
    concurrency scenarios -- this is a hard pass/fail gate, not a tunable
    threshold."

k6's own checks (see load_tests/scenarios/booking_hold_contention.js /
checkout_payment.js) only assert HTTP-level correctness during the run.
This script is the real assertion: it queries the database directly, after
the k6 run completes, for the two invariants that must hold no matter how
the HTTP layer behaved.

Lives in apps/backend/scripts/ (not load_tests/) and reuses
app.core.db.async_session_factory -- same database_url the running backend
service assembles for itself -- so this can run as a one-off ECS Fargate
task inside the VPC (see scripts/seed_load_test_data.py's docstring for why
that's required; GitHub-hosted Actions runners have no network path to the
private-subnet RDS Proxy). See .github/workflows/load-test-full.yml's
`verify-payment-correctness` job.

Exits non-zero (failing the CI job / gate run) if either invariant is
violated.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import text  # noqa: E402

from app.core.db import async_session_factory  # noqa: E402


async def check_no_overlapping_holds(session) -> list:
    """Self-join Transactions (app/models/transaction.py) on listing_id,
    looking for any pair of live (held/pending_payment/payment_received/
    released_to_wallet) rows whose possession_period_start_date/end_date
    ranges overlap -- the exact invariant the double-booking prevention
    rule (schema.md `Transaction.possessionPeriodEndDate`) exists to
    guarantee. `expired` and `failed` transactions are excluded -- an
    expired hold releasing the slot for someone else to book is correct
    behavior, not a violation. `payment_received`/`released_to_wallet` are
    the two escrow-model statuses (schema.md) that both mean "the guest
    paid" -- a released transaction's dates must still never double-book,
    same as before the escrow model existed.
    """
    result = await session.execute(
        text(
            """
            SELECT a.id, b.id, a.listing_id
            FROM transactions a
            JOIN transactions b
              ON a.listing_id = b.listing_id
             AND a.id < b.id
            WHERE a.status IN ('held', 'pending_payment', 'payment_received', 'released_to_wallet')
              AND b.status IN ('held', 'pending_payment', 'payment_received', 'released_to_wallet')
              AND a.possession_period_start_date < b.possession_period_end_date
              AND b.possession_period_start_date < a.possession_period_end_date
            """
        )
    )
    return result.all()


async def check_no_duplicate_charges(session) -> list:
    """Status lives directly on Transaction (no separate payments table --
    see app/models/transaction.py) and payment_processor_reference is the
    Paystack reference a webhook confirms against. A duplicate charge would
    show up as the SAME payment_processor_reference being attached to more
    than one paid row (`payment_received` or `released_to_wallet` --
    schema.md's escrow model; a transaction only ever reaches
    `released_to_wallet` by first passing through `payment_received`, so
    counting both together still catches the same duplicate-charge
    invariant) -- which the idempotency-key + webhook-signature-
    verification guarantees (architecture.md "Payment Correctness") should
    make structurally impossible even under replayed webhooks.
    """
    result = await session.execute(
        text(
            """
            SELECT payment_processor_reference, COUNT(*) AS succeeded_count
            FROM transactions
            WHERE status IN ('payment_received', 'released_to_wallet')
              AND payment_processor_reference IS NOT NULL
            GROUP BY payment_processor_reference
            HAVING COUNT(*) > 1
            """
        )
    )
    return result.all()


async def run() -> int:
    async with async_session_factory() as session:
        overlaps = await check_no_overlapping_holds(session)
        duplicates = await check_no_duplicate_charges(session)

    failed = False
    if overlaps:
        failed = True
        print(f"FAIL: {len(overlaps)} overlapping booking(s) detected -- double-booking occurred:")
        for a_id, b_id, listing_id in overlaps:
            print(f"  transactions {a_id} and {b_id} overlap on listing {listing_id}")
    else:
        print("PASS: no overlapping bookings detected.")

    if duplicates:
        failed = True
        print(f"FAIL: {len(duplicates)} payment reference(s) charged more than once:")
        for reference, count in duplicates:
            print(f"  payment_processor_reference {reference} has {count} succeeded transactions")
    else:
        print("PASS: no duplicate charges detected.")

    return 1 if failed else 0


def main() -> None:
    import asyncio

    sys.exit(asyncio.run(run()))


if __name__ == "__main__":
    main()
