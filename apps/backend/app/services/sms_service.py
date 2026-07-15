"""SMS delivery -- thin wrapper around Amazon SNS's direct-to-phone-number
publish.

Originally built for FEAT-001 phone sign-up/login OTP delivery; that flow
now runs entirely through Firebase Authentication's own phone/OTP flow
client-side (see auth_service.py's module docstring), so this module has
no active caller in this codebase as of that change. Left in place, not
deleted -- it's a working, tested integration (Amazon SNS, no separate
vendor credential needed) that a future backend-initiated SMS need (e.g. a
transactional alert unrelated to sign-in) can reuse directly.

Unlike Paystack/SES/FCM (app/core/config.py's other REPLACE_ME-gated
integrations), this needs no separate third-party vendor account or
secret -- SNS uses the same AWS account/IAM role already granted to this
task (infra/environments/*/iam.tf's sns:Publish statement). Still a no-op
until `aws_sns_sender_id` is a real value, though: Nigeria's mobile
networks filter SMS carrying an unregistered Sender ID, so a real one
must be registered with AWS SNS first, not just present in config.

Every external dependency call uses a bounded timeout (AGENTS.md Behavior
Rules) -- see _CLIENT_CONFIG. Raises SmsDeliveryError on failure rather
than swallowing it (unlike email_service.send_transactional_email, where a
missed marketing/confirmation email is recoverable) -- an SMS a caller
requested is usually time-sensitive, so failing loudly is the safer
default for any future caller.
"""

from __future__ import annotations

import logging
from functools import lru_cache
from typing import Any

import anyio
import boto3
from botocore.config import Config

from app.core.config import get_settings

logger = logging.getLogger("app.services.sms_service")

settings = get_settings()

# Bounded timeouts + limited retries -- a hung/degraded SNS must fail
# fast, never pile up slow requests against the API service's own
# capacity (AGENTS.md / architecture.md External Service Resilience).
_CLIENT_CONFIG = Config(connect_timeout=5, read_timeout=10, retries={"max_attempts": 2})


@lru_cache
def _get_client() -> Any:  # noqa: ANN401 -- boto3 has no first-party type stubs in this project
    return boto3.client(
        "sns",
        region_name=settings.aws_region,
        endpoint_url=settings.aws_endpoint_url or None,
        config=_CLIENT_CONFIG,
    )


class SmsDeliveryError(Exception):
    """Raised when an SMS genuinely fails to send (SNS unreachable/erroring),
    as opposed to the no-op "not configured yet" path, which returns
    normally -- see send_sms's docstring."""


async def send_sms(phone_number: str, message: str) -> None:
    """Sends `message` to `phone_number` via SNS.

    A no-op (logs and returns) when aws_sns_sender_id is still REPLACE_ME,
    matching every other third-party integration's REPLACE_ME-gated
    pattern -- this is the expected state in local/dev environments and
    lets FEAT-001's phone flow still be exercised end-to-end (the OTP is
    simply never actually delivered anywhere).

    Raises SmsDeliveryError if a real send genuinely fails -- callers
    must not treat this as best-effort the way email notifications are;
    see this module's docstring for why.
    """
    if settings.aws_sns_sender_id == "REPLACE_ME":
        logger.info(
            "sms_service: no-op send (SNS sender not configured) to=%s message=%s",
            phone_number,
            message,
        )
        return

    def _publish() -> None:
        _get_client().publish(
            PhoneNumber=phone_number,
            Message=message,
            MessageAttributes={
                "AWS.SNS.SMS.SenderID": {
                    "DataType": "String",
                    "StringValue": settings.aws_sns_sender_id,
                },
                # Transactional (not Promotional) -- prioritized for
                # delivery reliability/speed over cost, appropriate for a
                # time-sensitive OTP (AGENTS.md payment/OTP-adjacent
                # correctness expectations).
                "AWS.SNS.SMS.SMSType": {"DataType": "String", "StringValue": "Transactional"},
            },
        )

    try:
        await anyio.to_thread.run_sync(_publish)
    except Exception as exc:  # noqa: BLE001 -- boto3 raises many distinct exception types
        logger.exception("sms_service: failed to send SMS to=%s", phone_number)
        raise SmsDeliveryError(f"Failed to send SMS to {phone_number}") from exc
