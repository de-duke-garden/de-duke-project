"""FEAT-045 (Wallet Withdrawal via Automated Paystack Transfer) -- Payout
Settings half. A payee root (independent Host, or an agency's root
account -- same resolution as `agency_service._agency_root_id`/
`Transaction.payeeId`) saves the bank account their withdrawals pay out
to.

Verification flow (FEAT-045 AC: "resolution failure is shown clearly and
the record is not saved as 'verified'"): every save calls Paystack's
account-resolution API first. A resolution failure raises rather than
persisting anything with `verification_status='verified'` -- the caller
decides whether to still persist an 'unverified'/'failed' row for retry,
or reject the request outright (this module rejects outright; see
`save_payout_settings`).
"""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.wallet import PayoutSettings
from app.services import payment_service

logger_name = "app.services.payout_settings_service"


class PayoutSettingsError(Exception):
    """Raised for any payout-settings-level validation failure. Callers
    (app/api/v1/wallet.py) map this to HTTP 400/404 as appropriate."""


async def get_payout_settings(session: AsyncSession, *, owner_id: str) -> PayoutSettings | None:
    result = await session.execute(
        select(PayoutSettings).where(PayoutSettings.owner_id == owner_id)
    )
    return result.scalar_one_or_none()


async def save_payout_settings(
    session: AsyncSession,
    *,
    owner_id: str,
    account_number: str,
    bank_code: str,
    bank_name: str,
) -> PayoutSettings:
    """Resolves the account via Paystack (never trusts a client-supplied
    holder name), creates/refreshes the Paystack Transfer Recipient, and
    upserts the single PayoutSettings row for this owner. Raises
    PayoutSettingsError (never partially persists) if either Paystack call
    fails -- FEAT-045 AC.
    """
    try:
        resolved = await payment_service.resolve_bank_account(
            account_number=account_number, bank_code=bank_code
        )
    except payment_service.PaystackAccountResolutionError as exc:
        raise PayoutSettingsError(str(exc)) from exc
    except payment_service.PaystackNotConfiguredError as exc:
        raise PayoutSettingsError(str(exc)) from exc

    try:
        recipient_code = await payment_service.create_transfer_recipient(
            account_number=resolved.account_number,
            bank_code=bank_code,
            account_name=resolved.account_name,
        )
    except payment_service.PaystackNotConfiguredError as exc:
        raise PayoutSettingsError(str(exc)) from exc

    existing = await get_payout_settings(session, owner_id=owner_id)
    if existing is not None:
        existing.account_number = resolved.account_number
        existing.bank_code = bank_code
        existing.bank_name = bank_name
        existing.account_holder_name = resolved.account_name
        existing.verification_status = "verified"
        existing.paystack_recipient_code = recipient_code
        existing.updated_at = datetime.now(UTC)
        session.add(existing)
        settings_row = existing
    else:
        settings_row = PayoutSettings(
            owner_id=owner_id,
            account_number=resolved.account_number,
            bank_code=bank_code,
            bank_name=bank_name,
            account_holder_name=resolved.account_name,
            verification_status="verified",
            paystack_recipient_code=recipient_code,
        )
        session.add(settings_row)

    await session.flush()
    await session.refresh(settings_row)
    return settings_row
