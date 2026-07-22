"""FEAT-013 (Paystack Checkout) integration shape.

Built against `app.core.config.Settings.paystack_secret_key` /
`paystack_public_key` -- both still `REPLACE_ME` locally, so
`initiate_paystack_transaction` will raise/fail closed rather than
silently succeed until real keys are populated from Secrets Manager. No
real Paystack keys are fabricated anywhere in this module.

Webhook signature verification (`verify_webhook_signature` below) is keyed
off `paystack_secret_key` too, not a separate "webhook secret" -- Paystack
signs every webhook payload's HMAC with your account's ordinary SECRET
key; it doesn't issue a distinct value for this anywhere in its dashboard.
A prior `paystack_webhook_secret` config field suggested otherwise and was
a real source of confusion, so it was removed rather than kept as a
second name for the same value.

Idempotency: `InitiateCheckoutRequest.idempotency_key` (client-generated,
per AGENTS.md Coding Style Conventions) is persisted on first use
(`_idempotency_store` here is an in-process placeholder -- see TODO below)
so retries of the same checkout request never re-initiate a second Paystack
charge for the same held Transaction.

Signature verification: Paystack signs webhook payloads with an
HMAC-SHA512 of the raw request body using the webhook secret. We verify
that signature via `verify_webhook_signature` before a webhook payload is
ever trusted to mark a transaction succeeded -- per AGENTS.md Payment
Correctness: "never mark payment succeeded from client-reported result
alone."
"""

from __future__ import annotations

import hashlib
import hmac
import logging
from dataclasses import dataclass
from typing import Any

import httpx

from app.core.config import get_settings

logger = logging.getLogger("app.services.payment_service")

settings = get_settings()

PAYSTACK_BASE_URL = "https://api.paystack.co"
PAYSTACK_TIMEOUT_SECONDS = 10.0

# TODO(payments): replace with the shared Redis cache (per AGENTS.md
# "Rate limiting and hold-expiry counters live in the shared Cache (Redis)
# -- never per-task in-memory state"). The idempotency key -> Paystack
# reference mapping has the same statelessness requirement and must not
# live in per-task memory in production; this dict is a local-dev/test
# placeholder only. The real source of truth for "have we already
# initiated this checkout" is the `Transaction.payment_processor_reference`
# column set at initiation time (checked in checkout.py before calling
# this module at all), so this cache is a secondary guard, not the only one.
_idempotency_store: dict[str, str] = {}


class PaystackNotConfiguredError(Exception):
    """Raised when paystack_secret_key is still REPLACE_ME."""


@dataclass
class PaystackInitResult:
    authorization_url: str
    reference: str


def _require_configured() -> None:
    if settings.paystack_secret_key == "REPLACE_ME":
        raise PaystackNotConfiguredError(
            "paystack_secret_key is not configured (still REPLACE_ME) -- "
            "populate it from Secrets Manager before initiating live checkout."
        )


async def initiate_paystack_transaction(
    *,
    idempotency_key: str,
    email: str,
    amount_kobo: int,
    reference: str,
    metadata: dict,
) -> PaystackInitResult:
    """Calls Paystack's `POST /transaction/initialize`.

    Bounded timeout per AGENTS.md Behavior Rules (every external dependency
    call uses a bounded timeout + circuit breaker); callers should catch
    `httpx.HTTPError`/`PaystackNotConfiguredError` and degrade gracefully
    (surface a retryable "payment provider unavailable" error to the
    client, never silently mark anything succeeded).
    """
    cached_reference = _idempotency_store.get(idempotency_key)
    if cached_reference is not None:
        reference = cached_reference

    _require_configured()

    headers = {"Authorization": f"Bearer {settings.paystack_secret_key}"}
    payload = {
        "email": email,
        "amount": amount_kobo,
        "reference": reference,
        "metadata": metadata,
    }
    async with httpx.AsyncClient(
        base_url=PAYSTACK_BASE_URL, timeout=PAYSTACK_TIMEOUT_SECONDS
    ) as client:
        response = await client.post("/transaction/initialize", json=payload, headers=headers)
        response.raise_for_status()
        body = response.json()

    _idempotency_store[idempotency_key] = reference
    data = body.get("data", {})
    return PaystackInitResult(
        authorization_url=data.get("authorization_url", ""),
        reference=data.get("reference", reference),
    )


async def refund_paystack_transaction(*, reference: str, amount_kobo: int | None = None) -> None:
    """Calls Paystack's `POST /refund` -- FEAT-026 (Dispute & Refund
    Management), used when Staff/Admin resolve a dispute with
    "Resolve with Refund". `amount_kobo` omitted means a full refund of
    the original charge; dispute_service.py always passes an explicit
    amount (the Staff-entered refund_amount), since a dispute may resolve
    with a partial refund.

    Same bounded-timeout, fail-closed-if-unconfigured contract as
    `initiate_paystack_transaction` -- raises `PaystackNotConfiguredError`
    if keys aren't populated, and lets `httpx.HTTPError` propagate for the
    caller to catch and surface as a retryable failure (never silently
    treated as a successful refund).
    """
    _require_configured()

    headers = {"Authorization": f"Bearer {settings.paystack_secret_key}"}
    payload: dict[str, object] = {"transaction": reference}
    if amount_kobo is not None:
        payload["amount"] = amount_kobo

    async with httpx.AsyncClient(
        base_url=PAYSTACK_BASE_URL, timeout=PAYSTACK_TIMEOUT_SECONDS
    ) as client:
        response = await client.post("/refund", json=payload, headers=headers)
        response.raise_for_status()


@dataclass
class ResolvedAccount:
    account_number: str
    account_name: str


class PaystackAccountResolutionError(Exception):
    """Raised when Paystack rejects an account number/bank code
    combination (FEAT-045's Payout Settings AC: "a resolution failure is
    shown clearly and the record is not saved as 'verified'"). Distinct
    from `httpx.HTTPError` (a transport/connectivity failure) -- this is
    Paystack successfully responding that the account itself is invalid."""


async def resolve_bank_account(*, account_number: str, bank_code: str) -> ResolvedAccount:
    """Calls Paystack's `GET /bank/resolve` -- FEAT-045 Payout Settings AC:
    "Entering an account number + bank in Payout Settings triggers Paystack
    account resolution and shows the resolved account holder name for
    explicit confirmation before saving." Never trusts a client-supplied
    account holder name -- the name shown to the user for confirmation
    always comes from this call.
    """
    _require_configured()

    headers = {"Authorization": f"Bearer {settings.paystack_secret_key}"}
    params = {"account_number": account_number, "bank_code": bank_code}
    async with httpx.AsyncClient(
        base_url=PAYSTACK_BASE_URL, timeout=PAYSTACK_TIMEOUT_SECONDS
    ) as client:
        response = await client.get("/bank/resolve", params=params, headers=headers)
    if response.status_code >= 400:
        # Paystack returns 4xx with a human-readable `message` for an
        # invalid account/bank combination -- distinct from a genuine
        # transport failure, so this maps to PaystackAccountResolutionError
        # (a caller-correctable "check your details" case) rather than
        # propagating as httpx.HTTPError (a "the provider is down" case).
        try:
            detail = response.json().get("message", "Could not verify this account.")
        except ValueError:
            detail = "Could not verify this account."
        raise PaystackAccountResolutionError(detail)

    data = response.json().get("data", {})
    return ResolvedAccount(
        account_number=data.get("account_number", account_number),
        account_name=data.get("account_name", ""),
    )


@dataclass
class BankOption:
    name: str
    code: str


async def list_banks() -> list[BankOption]:
    """Calls Paystack's `GET /bank` (NGN, active only) -- backs FEAT-045's
    Payout Settings bank picker so a payee selects from Paystack's own
    canonical bank list (name + code) rather than typing a bank name/code
    freehand, which `resolve_bank_account` would then just reject anyway
    for any mismatch.
    """
    _require_configured()

    headers = {"Authorization": f"Bearer {settings.paystack_secret_key}"}
    params = {"currency": "NGN"}
    async with httpx.AsyncClient(
        base_url=PAYSTACK_BASE_URL, timeout=PAYSTACK_TIMEOUT_SECONDS
    ) as client:
        response = await client.get("/bank", params=params, headers=headers)
        response.raise_for_status()
        body = response.json()

    return [
        BankOption(name=b.get("name", ""), code=b.get("code", ""))
        for b in body.get("data", [])
        if b.get("code")
    ]


async def create_transfer_recipient(
    *, account_number: str, bank_code: str, account_name: str
) -> str:
    """Calls Paystack's `POST /transferrecipient` -- creates (or, if the
    same details are submitted again, Paystack itself dedupes) the
    Transfer Recipient a withdrawal's `POST /transfer` call references.
    Returns the `recipient_code` to store on `PayoutSettings.
    paystackRecipientCode` (schema.md). Called once when Payout Settings
    are first saved/changed (FEAT-045), not on every withdrawal.
    """
    _require_configured()

    headers = {"Authorization": f"Bearer {settings.paystack_secret_key}"}
    payload = {
        "type": "nuban",
        "name": account_name,
        "account_number": account_number,
        "bank_code": bank_code,
        "currency": "NGN",
    }
    async with httpx.AsyncClient(
        base_url=PAYSTACK_BASE_URL, timeout=PAYSTACK_TIMEOUT_SECONDS
    ) as client:
        response = await client.post("/transferrecipient", json=payload, headers=headers)
        response.raise_for_status()
        body = response.json()

    return body.get("data", {}).get("recipient_code", "")


@dataclass
class TransferResult:
    transfer_code: str
    reference: str
    status: str


async def initiate_transfer(
    *, recipient_code: str, amount_kobo: int, reference: str, reason: str
) -> TransferResult:
    """Calls Paystack's `POST /transfer` -- FEAT-045's automated withdrawal
    fulfillment. Fire-and-confirm: this call starting successfully does
    NOT mean the transfer completed -- `withdrawal_service.py` records the
    wallet debit and moves the WithdrawalRequest to `processing`
    immediately after this returns, then waits for Paystack's
    `transfer.success`/`transfer.failed` webhook event (handled in
    `paystack_webhook_handler.py`) to reach a terminal `paid`/`failed`
    state, mirroring how `initiate_paystack_transaction` above never
    itself marks a charge succeeded either.
    """
    _require_configured()

    headers = {"Authorization": f"Bearer {settings.paystack_secret_key}"}
    payload = {
        "source": "balance",
        "amount": amount_kobo,
        "recipient": recipient_code,
        "reference": reference,
        "reason": reason,
    }
    async with httpx.AsyncClient(
        base_url=PAYSTACK_BASE_URL, timeout=PAYSTACK_TIMEOUT_SECONDS
    ) as client:
        response = await client.post("/transfer", json=payload, headers=headers)
        response.raise_for_status()
        body = response.json()

    data: dict[str, Any] = body.get("data", {})
    return TransferResult(
        transfer_code=data.get("transfer_code", ""),
        reference=data.get("reference", reference),
        status=data.get("status", "pending"),
    )


def verify_webhook_signature(raw_body: bytes, signature_header: str | None) -> bool:
    """Verifies the `x-paystack-signature` header against an HMAC-SHA512
    of the raw request body, keyed by `paystack_secret_key` -- Paystack
    signs webhook payloads with your account's SECRET key directly, not a
    separate value (there is no distinct "webhook secret" anywhere in the
    Paystack dashboard to configure here).

    Per AGENTS.md Payment Correctness, this MUST return True before any
    webhook payload is used to transition a Transaction to
    `payment_received`.
    """
    if not signature_header:
        return False
    if settings.paystack_secret_key == "REPLACE_ME":
        logger.warning(
            "payment_service: paystack_secret_key not configured -- "
            "rejecting webhook (fail closed)"
        )
        return False
    computed = hmac.new(
        settings.paystack_secret_key.encode("utf-8"),
        raw_body,
        hashlib.sha512,
    ).hexdigest()
    return hmac.compare_digest(computed, signature_header)
