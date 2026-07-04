"""FEAT-013 (Paystack Checkout) integration shape.

Built against `app.core.config.Settings.paystack_secret_key` /
`paystack_public_key` / `paystack_webhook_secret` -- all still `REPLACE_ME`
locally, so `initiate_paystack_transaction` will raise/fail closed rather
than silently succeed until real keys are populated from Secrets Manager.
No real Paystack keys are fabricated anywhere in this module.

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


def verify_webhook_signature(raw_body: bytes, signature_header: str | None) -> bool:
    """Verifies the `x-paystack-signature` header against an HMAC-SHA512
    of the raw request body, keyed by `paystack_webhook_secret`.

    Per AGENTS.md Payment Correctness, this MUST return True before any
    webhook payload is used to transition a Transaction to `succeeded`.
    """
    if not signature_header:
        return False
    if settings.paystack_webhook_secret == "REPLACE_ME":
        logger.warning(
            "payment_service: paystack_webhook_secret not configured -- "
            "rejecting webhook (fail closed)"
        )
        return False
    computed = hmac.new(
        settings.paystack_webhook_secret.encode("utf-8"),
        raw_body,
        hashlib.sha512,
    ).hexdigest()
    return hmac.compare_digest(computed, signature_header)
