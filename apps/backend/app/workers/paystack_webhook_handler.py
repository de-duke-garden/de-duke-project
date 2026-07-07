"""FEAT-013 -- Paystack webhook processing, factored out of the API route so
it can be unit tested without going through the HTTP layer, and so its
signature-verification gate is visible and testable in isolation.

Behavior Rule (AGENTS.md): never mark a payment/booking "succeeded" from a
client-reported result alone -- only a verified, signature-checked Paystack
webhook (this module) may transition a Transaction to `succeeded`.
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.transaction import Receipt, Transaction
from app.services.commission_service import compute_breakdown, get_effective_rate
from app.services.email_service import (
    HOST_PAYOUT_SUMMARY,
    PAYMENT_FAILED,
    PAYMENT_SUCCEEDED,
    notify_user,
)
from app.services.payment_service import verify_webhook_signature


class WebhookVerificationError(Exception):
    """Raised when the webhook signature does not verify -- caller must
    respond 401/400 and must NOT process `event`/`data`."""


async def handle_paystack_webhook(
    session: AsyncSession,
    *,
    raw_body: bytes,
    signature_header: str | None,
    event: str,
    data: dict,
) -> Transaction | None:
    if not verify_webhook_signature(raw_body, signature_header):
        raise WebhookVerificationError("Invalid Paystack webhook signature")

    reference = data.get("reference")
    if not reference:
        return None

    result = await session.execute(
        select(Transaction)
        .where(Transaction.payment_processor_reference == reference)
        .with_for_update()
    )
    txn = result.scalar_one_or_none()
    if txn is None:
        return None

    # Idempotent: a webhook may be delivered more than once by Paystack.
    if txn.status in ("succeeded", "failed", "refunded"):
        return txn

    if event == "charge.success" and data.get("status") == "success":
        rate = await get_effective_rate(session, txn.transaction_type, as_of=txn.created_at)
        commission_amount, net_payout_amount = compute_breakdown(txn.gross_amount, rate)
        txn.status = "succeeded"
        txn.paid_at = datetime.now(UTC)
        txn.commission_amount = commission_amount
        txn.net_payout_amount = net_payout_amount
        session.add(txn)

        receipt = Receipt(
            transaction_id=txn.id,
            receipt_number=f"RCPT-{txn.id[:8].upper()}",
            pdf_url="",  # TODO(payments): generate/store real receipt PDF in S3
        )
        session.add(receipt)
        await session.commit()

        await notify_user(
            session,
            user_id=txn.payer_id,
            template=PAYMENT_SUCCEEDED,
            context={
                "transaction_id": txn.id,
                "gross_amount": txn.gross_amount,
                "commission_amount": txn.commission_amount,
                "net_payout_amount": txn.net_payout_amount,
            },
        )
        # FEAT-024 AC: "Host receives an email payout summary (gross,
        # commission, net) when a transaction involving their listing
        # completes." payee_id is the host being paid out (payer_id is the
        # seeker who paid) -- see Transaction.payerId/payeeId in schema.md.
        await notify_user(
            session,
            user_id=txn.payee_id,
            template=HOST_PAYOUT_SUMMARY,
            context={
                "transaction_id": txn.id,
                "gross_amount": txn.gross_amount,
                "commission_amount": txn.commission_amount,
                "net_payout_amount": txn.net_payout_amount,
            },
        )
    else:
        txn.status = "failed"
        session.add(txn)
        await session.commit()

        await notify_user(
            session,
            user_id=txn.payer_id,
            template=PAYMENT_FAILED,
            context={"transaction_id": txn.id},
        )

    return txn
