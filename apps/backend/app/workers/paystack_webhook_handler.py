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
from app.services import analytics_service, push_service
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

        payment_success_context = {
            "transaction_id": txn.id,
            "gross_amount": txn.gross_amount,
            "commission_amount": txn.commission_amount,
            "net_payout_amount": txn.net_payout_amount,
        }
        await notify_user(
            session,
            user_id=txn.payer_id,
            template=PAYMENT_SUCCEEDED,
            context=payment_success_context,
        )
        # FEAT-022: push shares this trigger event with email -- see
        # bookings.py's identical comment for the shared rationale. Only
        # the payer's PAYMENT_SUCCEEDED gets a push, not the host's payout
        # summary -- FEAT-022's AC scope is "payment success/failure" from
        # the payer's perspective, not the payout-summary detail email is
        # the durable record for (FEAT-024's own, email-specific AC).
        await push_service.notify_user(
            session,
            user_id=txn.payer_id,
            template=push_service.PAYMENT_SUCCEEDED,
            context=payment_success_context,
        )
        # FEAT-024 AC: "Host receives an email payout summary (gross,
        # commission, net) when a transaction involving their listing
        # completes." payee_id is the host being paid out (payer_id is the
        # seeker who paid) -- see Transaction.payerId/payeeId in schema.md.
        await notify_user(
            session,
            user_id=txn.payee_id,
            template=HOST_PAYOUT_SUMMARY,
            context=payment_success_context,
        )
        # FEAT-028: no raw payment gateway details (no
        # payment_processor_reference, no card/authorization data) --
        # only IDs and the amounts already needed for FEAT-035's Gross
        # Transaction Value / commission revenue metrics.
        await analytics_service.track_event(
            event_name=analytics_service.PAYMENT_COMPLETED,
            user_id=txn.payer_id,
            properties={
                "transaction_id": txn.id,
                "listing_id": txn.listing_id,
                "transaction_type": txn.transaction_type,
                "gross_amount": txn.gross_amount,
                "commission_amount": txn.commission_amount,
            },
        )
        # FEAT-016 AC: "Analytics capture chat-to-payment conversion rate
        # for ongoing monitoring." Fired alongside PAYMENT_COMPLETED for
        # every successful payment -- the Admin Web Console analytics
        # dashboard computes the conversion rate against CHAT_STARTED
        # volume for the same listing (chat_service.create_conversation
        # already fires CHAT_STARTED), rather than requiring this worker
        # to look up whether a specific chat thread preceded this payment.
        await analytics_service.track_event(
            event_name=analytics_service.CHAT_TO_PAYMENT_CONVERSION,
            user_id=txn.payer_id,
            properties={"transaction_id": txn.id, "listing_id": txn.listing_id},
        )
    else:
        txn.status = "failed"
        session.add(txn)
        await session.commit()

        payment_failed_context = {"transaction_id": txn.id}
        await notify_user(
            session,
            user_id=txn.payer_id,
            template=PAYMENT_FAILED,
            context=payment_failed_context,
        )
        await push_service.notify_user(
            session,
            user_id=txn.payer_id,
            template=push_service.PAYMENT_FAILED,
            context=payment_failed_context,
        )

    return txn
