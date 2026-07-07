"""Tests for app/services/sms_service.py -- FEAT-001 phone OTP delivery
via Amazon SNS. Never hits real SNS -- the boto3 client is monkeypatched.
"""

from __future__ import annotations

from unittest.mock import MagicMock

import pytest

from app.services import sms_service


@pytest.fixture(autouse=True)
def _clear_client_cache():
    """_get_client is @lru_cache-d -- clear before each test so settings
    overrides in one test don't leak a stale client into the next (same
    reasoning as test_storage.py's identical fixture)."""
    sms_service._get_client.cache_clear()


async def test_send_sms_no_ops_when_sender_id_unconfigured(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(sms_service.settings, "aws_sns_sender_id", "REPLACE_ME")
    fake_client = MagicMock()
    monkeypatch.setattr(sms_service, "_get_client", lambda: fake_client)

    await sms_service.send_sms("+2348012345678", "your code is 123456")

    fake_client.publish.assert_not_called()


async def test_send_sms_calls_sns_publish_with_expected_attributes(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(sms_service.settings, "aws_sns_sender_id", "DeDuke")
    fake_client = MagicMock()
    monkeypatch.setattr(sms_service, "_get_client", lambda: fake_client)

    await sms_service.send_sms("+2348012345678", "your code is 123456")

    fake_client.publish.assert_called_once()
    call_kwargs = fake_client.publish.call_args.kwargs
    assert call_kwargs["PhoneNumber"] == "+2348012345678"
    assert call_kwargs["Message"] == "your code is 123456"
    assert call_kwargs["MessageAttributes"]["AWS.SNS.SMS.SenderID"]["StringValue"] == "DeDuke"
    assert call_kwargs["MessageAttributes"]["AWS.SNS.SMS.SMSType"]["StringValue"] == "Transactional"


async def test_send_sms_raises_sms_delivery_error_on_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(sms_service.settings, "aws_sns_sender_id", "DeDuke")
    fake_client = MagicMock()
    fake_client.publish.side_effect = RuntimeError("SNS unavailable")
    monkeypatch.setattr(sms_service, "_get_client", lambda: fake_client)

    with pytest.raises(sms_service.SmsDeliveryError):
        await sms_service.send_sms("+2348012345678", "your code is 123456")
