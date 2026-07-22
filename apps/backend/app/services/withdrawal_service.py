"""FEAT-045 (Wallet Withdrawal via Automated Paystack Transfer) --
Withdrawal half. No further Admin approval at this step: the deliberate
checkpoint is FEAT-043's escrow release, which already required a De-Duke
Admin to move funds into the wallet in the first place -- once money is in
a payee's Wallet, they can withdraw it themselves.

Debit-then-transfer ordering (money-safety): the wallet is debited and the
WithdrawalRequest row created inside the SAME DB transaction as the
Paystack Transfer API call being *initiated* -- never after. If the
Paystack call itself fails/times out, the whole transaction (including the
debit) rolls back, so a failed transfer attempt never leaves a payee's
balance silently short. Once `initiate_transfer` has returned successfully
though, the debit is final and the WithdrawalRequest sits `processing`
until Paystack's `transfer.success`/`transfer.failed` webhook (handled in
paystack_webhook_handler.py) reaches a terminal state -- a `transfer.failed`
webhook reverses the debit via a `withdrawal_reversal` ledger entry, never
by mutating/deleting the original debit row (ledger entries are immutable).
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime
from uuid import uuid4

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.wallet import PayoutSettings, Wallet, WalletTransaction, WithdrawalRequest
from app.services import payment_service

logger = logging.getLogger("app.services.withdrawal_service")


class WithdrawalError(Exception):
    """Raised for any withdrawal-service-level validation failure.
    Callers (app/api/v1/wallet.py) map this to HTTP 400/404/503 as
    appropriate."""


async def request_withdrawal(
    session: AsyncSession, *, wallet: Wallet, amount: float, requested_by_id: str
) -> WithdrawalRequest:
    if amount <= 0:
        raise WithdrawalError("Withdrawal amount must be positive.")
    if amount > wallet.balance:
        raise WithdrawalError("Withdrawal amount exceeds available wallet balance.")

    result = await session.execute(
        select(PayoutSettings).where(PayoutSettings.owner_id == wallet.owner_id)
    )
    payout_settings = result.scalar_one_or_none()
    if payout_settings is None or payout_settings.verification_status != "verified":
        raise WithdrawalError(
            "Add and verify your payout bank account in Payout Settings before withdrawing."
        )
    if not payout_settings.paystack_recipient_code:
        raise WithdrawalError(
            "Your payout account is not ready for transfers yet -- re-save your Payout "
            "Settings to retry."
        )

    reference = f"wd_{uuid4()}"
    try:
        transfer = await payment_service.initiate_transfer(
            recipient_code=payout_settings.paystack_recipient_code,
            amount_kobo=int(round(amount * 100)),
            reference=reference,
            reason="De-Duke wallet withdrawal",
        )
    except payment_service.PaystackNotConfiguredError as exc:
        raise WithdrawalError(str(exc)) from exc
    except httpx.HTTPError as exc:
        logger.warning("withdrawal_service: paystack transfer failed: %s", exc)
        raise WithdrawalError(
            "Payment provider is temporarily unavailable. Please retry."
        ) from exc

    new_balance = round(wallet.balance - amount, 2)
    withdrawal = WithdrawalRequest(
        wallet_id=wallet.id,
        amount=amount,
        payout_settings_id=payout_settings.id,
        status="processing",
        requested_by_id=requested_by_id,
        paystack_transfer_reference=transfer.reference,
    )
    session.add(withdrawal)
    await session.flush()

    session.add(
        WalletTransaction(
            wallet_id=wallet.id,
            direction="debit",
            amount=amount,
            source_type="withdrawal",
            source_id=withdrawal.id,
            balance_after=new_balance,
        )
    )
    wallet.balance = new_balance
    wallet.updated_at = datetime.now(UTC)
    session.add(wallet)

    await session.flush()
    await session.refresh(withdrawal)
    return withdrawal


async def list_withdrawals(session: AsyncSession, *, wallet_id: str) -> list[WithdrawalRequest]:
    result = await session.execute(
        select(WithdrawalRequest)
        .where(WithdrawalRequest.wallet_id == wallet_id)
        .order_by(WithdrawalRequest.requested_at.desc())
    )
    return list(result.scalars().all())


async def handle_transfer_webhook(
    session: AsyncSession, *, event: str, reference: str
) -> WithdrawalRequest | None:
    """Called from paystack_webhook_handler.py for `transfer.success` /
    `transfer.failed` events. Idempotent on `withdrawal.status` -- a
    replayed webhook for an already-terminal WithdrawalRequest is a no-op,
    same idempotency contract as `handle_paystack_webhook`'s charge.success
    handling.
    """
    result = await session.execute(
        select(WithdrawalRequest)
        .where(WithdrawalRequest.paystack_transfer_reference == reference)
        .with_for_update()
    )
    withdrawal = result.scalar_one_or_none()
    if withdrawal is None or withdrawal.status in ("paid", "failed"):
        return withdrawal

    if event == "transfer.success":
        withdrawal.status = "paid"
        withdrawal.fulfilled_at = datetime.now(UTC)
        session.add(withdrawal)
    elif event == "transfer.failed":
        withdrawal.status = "failed"
        withdrawal.fulfilled_at = datetime.now(UTC)
        withdrawal.failure_reason = "Paystack reported the transfer failed."
        session.add(withdrawal)

        # Reversal: credit the wallet back via a NEW immutable ledger
        # entry (never mutate/delete the original debit row) so the
        # ledger remains a complete, auditable history of exactly what
        # happened and when.
        wallet = await session.get(Wallet, withdrawal.wallet_id)
        if wallet is not None:
            new_balance = round(wallet.balance + withdrawal.amount, 2)
            session.add(
                WalletTransaction(
                    wallet_id=wallet.id,
                    direction="credit",
                    amount=withdrawal.amount,
                    source_type="withdrawal_reversal",
                    source_id=withdrawal.id,
                    balance_after=new_balance,
                    notes="Reversed: Paystack transfer failed.",
                )
            )
            wallet.balance = new_balance
            wallet.updated_at = datetime.now(UTC)
            session.add(wallet)

    await session.flush()
    await session.refresh(withdrawal)
    return withdrawal
