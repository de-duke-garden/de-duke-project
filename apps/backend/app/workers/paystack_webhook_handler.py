"""FEAT-013 -- Paystack webhook processing, factored out of the API route so
it can be unit tested without going through the HTTP layer, and so its
signature-verification gate is visible and testable in isolation.

Behavior Rule (AGENTS.md): never mark a payment "received" from a
client-reported result alone -- only a verified, signature-checked Paystack
webhook (this module) may transition a Transaction to `payment_received`.

Escrow model note (schema.md, FEAT-043): a successful charge here only
means the money landed in De-Duke's own Paystack settlement account -- it
does NOT mean the host/agency has been paid. `HOST_PAYOUT_SUMMARY` is
deliberately NOT sent from this module anymore (see wallet_service.py's
`release_transaction` instead) -- sending a "payout summary" the instant a
guest pays would tell the host they'd been paid before a De-Duke Admin has
actually released anything to their Wallet, exactly the ambiguity this
whole escrow model exists to remove.
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.transaction import Transaction
from app.services import analytics_service, push_service
from app.services.email_service import PAYMENT_FAILED, PAYMENT_SUCCEEDED, notify_user
from app.services.payment_service import verify_webhook_signature
from app.services.receipt_service import ensure_receipt
from app.services.withdrawal_service import handle_transfer_webhook


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
):
    if not verify_webhook_signature(raw_body, signature_header):
        raise WebhookVerificationError("Invalid Paystack webhook signature")

    reference = data.get("reference")
    if not reference:
        return None

    # FEAT-045: transfer.success/transfer.failed are withdrawal-fulfillment
    # events, not charge events -- distinct handling path (WithdrawalRequest,
    # not Transaction), routed to withdrawal_service rather than the
    # charge.success/else branching below.
    if event in ("transfer.success", "transfer.failed"):
        async with session.begin():
            return await handle_transfer_webhook(session, event=event, reference=reference)

    result = await session.execute(
        select(Transaction)
        .where(Transaction.payment_processor_reference == reference)
        .with_for_update()
    )
    txn = result.scalar_one_or_none()
    if txn is None:
        return None

    # Idempotent: a webhook may be delivered more than once by Paystack.
    if txn.status in ("payment_received", "released_to_wallet", "failed", "refunded"):
        return txn

    if event == "charge.success" and data.get("status") == "success":
        # Two-sided commission model (product decision): gross_amount/
        # commission_amount/net_payout_amount are already final, snapshotted
        # at hold-creation time (booking_service.confirm_booking) -- the
        # charge amount itself had to include the buyer fee before checkout
        # could even initiate the Paystack transaction, so recomputing the
        # breakdown here (the old single-rate model's behavior) would be
        # both redundant and wrong (it would ignore listing_price/
        # buyer_fee_amount entirely). This handler only flips status/paid_at.
        txn.status = "payment_received"
        txn.paid_at = datetime.now(UTC)
        session.add(txn)
        await session.commit()

        # Upgrades the hold-confirmation PDF `bookings.py` generated when
        # this transaction was first created into a full payment receipt
        # (same Receipt row, now-final commission breakdown) -- called
        # AFTER the commit above so the PDF reflects the just-committed
        # payment_received/paid_at/commission values, not values about to
        # be rolled back if this function raised before reaching here. See
        # receipt_service.py's module docstring.
        await ensure_receipt(session, txn)

        payment_success_context = {
            "transaction_id": txn.id,
            "gross_amount": txn.gross_amount,
            "commission_amount": txn.commission_amount,
            "net_payout_amount": txn.net_payout_amount,
        }
        # Only the PAYER is notified here -- the money hasn't gone
        # anywhere yet as far as the payee is concerned (it's sitting in
        # De-Duke's own settlement account as escrow, per schema.md's
        # Escrow model). The payee's own notification
        # (HOST_PAYOUT_SUMMARY) now fires from wallet_service.py's
        # `release_transaction`, at the point a De-Duke Admin actually
        # releases funds to their Wallet (FEAT-043) -- see this module's
        # docstring for why sending it here would be actively misleading.
        await notify_user(
            session,
            user_id=txn.payer_id,
            template=PAYMENT_SUCCEEDED,
            context=payment_success_context,
        )
        await push_service.notify_user(
            session,
            user_id=txn.payer_id,
            template=push_service.PAYMENT_SUCCEEDED,
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
