"""FEAT-013 -- Paystack Checkout endpoints.

Payment Correctness (AGENTS.md): this router only ever *initiates* a
Paystack transaction and returns an authorization URL -- it never marks a
Transaction `succeeded` itself. Only `paystack_webhook_handler.py`,
reached via the `/webhook` route below after signature verification, may
do that.
"""

from __future__ import annotations

import logging

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.db import get_session
from app.core.security import CurrentUser, get_current_user
from app.models.transaction import Transaction
from app.models.user import User
from app.schemas.transaction import InitiateCheckoutRequest, InitiateCheckoutResponse
from app.services.booking_service import is_hold_active
from app.services.payment_service import PaystackNotConfiguredError, initiate_paystack_transaction
from app.workers.paystack_webhook_handler import WebhookVerificationError, handle_paystack_webhook

logger = logging.getLogger("app.api.v1.checkout")

router = APIRouter()
settings = get_settings()


@router.post("/initiate", response_model=InitiateCheckoutResponse)
async def initiate_checkout(
    body: InitiateCheckoutRequest,
    current_user: CurrentUser = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> InitiateCheckoutResponse:
    async with session.begin():
        result = await session.execute(
            select(Transaction).where(Transaction.id == body.transaction_id).with_for_update()
        )
        txn = result.scalar_one_or_none()
        if txn is None or txn.payer_id != current_user.user_id:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Booking not found")
        if not is_hold_active(txn):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Booking hold is no longer active. Please start again.",
            )

        # Idempotency: if this transaction already has a processor
        # reference, this idempotency key (or a prior retry) already
        # initiated a Paystack transaction -- never initiate a second one.
        if txn.payment_processor_reference:
            return InitiateCheckoutResponse(
                transaction_id=txn.id,
                status=txn.status,
                authorization_url="",
                paystack_reference=txn.payment_processor_reference,
            )

        # Bug fix: this used to pass `current_user.user_id` (a bare UUID)
        # as `email` -- Paystack's `/transaction/initialize` validates
        # `email` as an actual email address and rejects anything else
        # with a 400, which is exactly what surfaced to the client as a
        # 502 "Payment provider is temporarily unavailable" below. Firebase
        # phone/OTP sign-in (FEAT-001) never collects an email at all, so
        # `User.email` is genuinely nullable here -- falls back to
        # `settings.paystack_fallback_email` (a shared support address,
        # not a fabricated per-user one) rather than failing checkout
        # entirely over a field Paystack only uses for its own receipt
        # email, not anything this app relies on. Real accounts with an
        # email on file (Google/Firebase email sign-in) always get their
        # real one.
        user = await session.get(User, current_user.user_id)
        payer_email = (user.email if user is not None else None) or (
            settings.paystack_fallback_email
        )

        reference = f"txn_{txn.id}"
        try:
            result_init = await initiate_paystack_transaction(
                idempotency_key=body.idempotency_key,
                email=payer_email,
                amount_kobo=int(round(txn.gross_amount * 100)),
                reference=reference,
                metadata={"transaction_id": txn.id, "idempotency_key": body.idempotency_key},
            )
        except PaystackNotConfiguredError as exc:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Payment provider is not configured yet.",
            ) from exc
        except httpx.HTTPError as exc:
            logger.warning("checkout: paystack initiate failed: %s", exc)
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail="Payment provider is temporarily unavailable. Please retry.",
            ) from exc

        txn.status = "pending_payment"
        txn.payment_processor_reference = result_init.reference
        session.add(txn)

    return InitiateCheckoutResponse(
        transaction_id=txn.id,
        status=txn.status,
        authorization_url=result_init.authorization_url,
        paystack_reference=result_init.reference,
    )


@router.post("/webhook", status_code=status.HTTP_200_OK)
async def paystack_webhook(
    request: Request,
    x_paystack_signature: str | None = Header(default=None),
    session: AsyncSession = Depends(get_session),
) -> dict[str, str]:
    """Verifies Paystack's HMAC signature before ever trusting the payload
    (AGENTS.md Payment Correctness). Returns 401 on a bad signature."""
    raw_body = await request.body()
    try:
        payload = await request.json()
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid JSON body"
        ) from exc

    try:
        await handle_paystack_webhook(
            session,
            raw_body=raw_body,
            signature_header=x_paystack_signature,
            event=payload.get("event", ""),
            data=payload.get("data", {}),
        )
    except WebhookVerificationError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(exc)) from exc

    return {"status": "ok"}
