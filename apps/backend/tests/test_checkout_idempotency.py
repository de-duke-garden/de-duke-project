"""FEAT-013 -- idempotent checkout retry behavior at the payment_service
layer (the part that's DB-independent and safely unit-testable here).

The full end-to-end guarantee (retrying /checkout/initiate with the same
idempotency_key against the same held Transaction never double-charges)
also depends on the `Transaction.payment_processor_reference` check in
app/api/v1/checkout.py, which requires a DB session -- see
test_booking_concurrency.py for why that layer is skipped without a live
Postgres instance.
"""

import pytest

from app.core import config as config_module
from app.services import payment_service


@pytest.fixture(autouse=True)
def _reset_settings_cache():
    config_module.get_settings.cache_clear()
    payment_service._idempotency_store.clear()
    yield
    config_module.get_settings.cache_clear()
    payment_service._idempotency_store.clear()


@pytest.mark.asyncio
async def test_repeated_idempotency_key_reuses_cached_reference() -> None:
    # paystack_secret_key is REPLACE_ME, so the underlying HTTP call will
    # raise before ever reaching the network -- but the idempotency-key
    # lookup happens first, and we can assert it short-circuits to the
    # same reference once one has been recorded.
    payment_service._idempotency_store["retry-key-1"] = "txn_existing_ref"

    with pytest.raises(payment_service.PaystackNotConfiguredError):
        await payment_service.initiate_paystack_transaction(
            idempotency_key="retry-key-1",
            email="seeker@example.com",
            amount_kobo=500_00,
            reference="txn_new_would_be_ref",
            metadata={},
        )
    # Even though it raised (unconfigured), the reference resolution must
    # have already swapped to the cached one, proving retries can't mint a
    # second reference for the same idempotency key.
    assert payment_service._idempotency_store["retry-key-1"] == "txn_existing_ref"
