"""FEAT-032 -- Hold-expiry background job.

Transitions `held`/`pending_payment` Transaction rows whose `hold_expires_at`
has passed into `expired`. Intended to be invoked periodically by the
Background Task Processor (SQS-driven, per architecture.md) -- this module
only exposes the pure transition function; wiring an SQS-triggered
scheduled invocation is an infra/worker-harness concern outside this slice.

Per risk_log.md R-018 (hold-expiry job monitoring), this function returns
the count of transitioned rows so a caller can emit a metric/alert if it
silently stops running or expires an anomalously large batch.
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.transaction import Transaction
from app.services import push_service
from app.services.email_service import BOOKING_HOLD_EXPIRED, notify_user


async def expire_stale_holds(session: AsyncSession) -> int:
    """Finds all `held`/`pending_payment` transactions past their
    `hold_expires_at` and transitions them to `expired`. Commits the
    session. Returns the number of transactions expired.
    """
    now = datetime.now(UTC)
    result = await session.execute(
        select(Transaction)
        .where(Transaction.status.in_(("held", "pending_payment")))
        .where(Transaction.hold_expires_at.isnot(None))
        .where(Transaction.hold_expires_at < now)
        .with_for_update()
    )
    stale = list(result.scalars().all())
    for txn in stale:
        txn.status = "expired"
        session.add(txn)

    await session.commit()

    for txn in stale:
        # Best-effort notification; a failure here must never roll back the
        # already-committed expiry transition.
        notification_context = {"transaction_id": txn.id, "listing_id": txn.listing_id}
        try:
            await notify_user(
                session,
                user_id=txn.payer_id,
                template=BOOKING_HOLD_EXPIRED,
                context=notification_context,
            )
        except Exception:  # noqa: BLE001 -- best-effort notification only
            pass
        # FEAT-022: push shares this trigger event with email -- see
        # bookings.py's identical comment for the shared rationale.
        try:
            await push_service.notify_user(
                session,
                user_id=txn.payer_id,
                template=push_service.BOOKING_HOLD_EXPIRED,
                context=notification_context,
            )
        except Exception:  # noqa: BLE001 -- best-effort notification only
            pass

    return len(stale)
