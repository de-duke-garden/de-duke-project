"""Unit tests for FEAT-013 Paystack webhook signature verification and the
"never invent Paystack keys" fail-closed behavior."""

import hashlib
import hmac

import pytest

from app.core import config as config_module
from app.services import payment_service


@pytest.fixture(autouse=True)
def _reset_settings_cache():
    config_module.get_settings.cache_clear()
    yield
    config_module.get_settings.cache_clear()


def test_verify_webhook_signature_rejects_missing_header() -> None:
    assert payment_service.verify_webhook_signature(b"{}", None) is False


def test_verify_webhook_signature_fails_closed_when_unconfigured() -> None:
    # settings.paystack_secret_key is REPLACE_ME by default in this env
    assert payment_service.verify_webhook_signature(b"{}", "somesignature") is False


def test_verify_webhook_signature_accepts_correct_hmac(monkeypatch) -> None:
    monkeypatch.setattr(payment_service.settings, "paystack_secret_key", "test-secret")
    body = b'{"event": "charge.success"}'
    signature = hmac.new(b"test-secret", body, hashlib.sha512).hexdigest()
    assert payment_service.verify_webhook_signature(body, signature) is True


def test_verify_webhook_signature_rejects_tampered_body(monkeypatch) -> None:
    monkeypatch.setattr(payment_service.settings, "paystack_secret_key", "test-secret")
    body = b'{"event": "charge.success"}'
    signature = hmac.new(b"test-secret", body, hashlib.sha512).hexdigest()
    tampered_body = b'{"event": "charge.success", "data": {"amount": 999999}}'
    assert payment_service.verify_webhook_signature(tampered_body, signature) is False


@pytest.mark.asyncio
async def test_initiate_paystack_transaction_raises_when_unconfigured() -> None:
    # paystack_secret_key is REPLACE_ME by default -- must fail closed, never
    # silently proceed with a fabricated key.
    with pytest.raises(payment_service.PaystackNotConfiguredError):
        await payment_service.initiate_paystack_transaction(
            idempotency_key="test-key-12345",
            email="guest@example.com",
            amount_kobo=1_000_00,
            reference="txn_test",
            metadata={},
        )
