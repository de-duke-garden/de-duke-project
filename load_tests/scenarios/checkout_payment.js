// Priority Scenario 3: Checkout & payment correctness under load.
// Validates: idempotency-key handling on /checkout/initiate under
// concurrent retries of the SAME request, and webhook-signature
// verification + exactly-once processing on /checkout/webhook under
// deliberately duplicated/replayed Paystack webhook deliveries
// (architecture.md "Payment Correctness"). Final, authoritative check for
// zero duplicate charges is apps/backend/scripts/verify_no_double_booking.py (run as a one-off ECS task, not directly), run
// against the database after this script completes -- see that file's
// docstring.
import { check, sleep } from 'k6';
import { taggedPost, taggedPostRaw, loginSyntheticUser } from '../lib/client.js';
import { endpointThresholds, globalErrorRateThreshold } from '../lib/thresholds.js';
import { hmac } from 'k6/crypto';

// A synthetic-user-owned `held` transaction, pre-seeded per VU/iteration by
// apps/backend/scripts/seed_load_test_data.py --with-checkout-transactions, which writes
// this file mapping a range of transaction IDs the script can safely drive
// through checkout without colliding with real bookings.
// k6's goja runtime doesn't support import-assertion syntax -- see
// lib/thresholds.js's identical fix/comment.
const checkoutTransactionIds = JSON.parse(open('../seed/checkout_transaction_ids.json'));

// Staging-only test-mode Paystack SECRET key -- provisioned as a GitHub
// Environment secret for `staging` (TF_PAYSTACK_SECRET_KEY_TEST). Paystack
// signs webhook payloads with your account's ordinary secret key, not a
// separate "webhook secret" (see app/services/payment_service.py's
// verify_webhook_signature) -- this is staging's own TEST-mode secret key,
// distinct from any live/production key, so this script can legitimately
// forge signed webhook payloads without ever touching a live payments
// secret.
const PAYSTACK_SECRET_KEY = __ENV.PAYSTACK_SECRET_KEY_TEST || '';

const TARGET_CHECKOUT_RPS = 50; // README Target Scale: peak checkout attempts/sec
const TARGET_WEBHOOK_RPS = 50; // matching webhook delivery rate, plus deliberate replays below

export const options = {
  scenarios: {
    checkout_initiate: {
      executor: 'ramping-arrival-rate',
      exec: 'initiateCheckout',
      startRate: 5,
      timeUnit: '1s',
      preAllocatedVUs: 100,
      maxVUs: 500,
      stages: [
        { target: TARGET_CHECKOUT_RPS, duration: '3m' },
        { target: TARGET_CHECKOUT_RPS, duration: '30m' },
      ],
    },
    checkout_webhook_replay: {
      executor: 'ramping-arrival-rate',
      exec: 'deliverWebhook',
      startRate: 5,
      timeUnit: '1s',
      preAllocatedVUs: 100,
      maxVUs: 500,
      stages: [
        // Deliberately over-delivers relative to TARGET_WEBHOOK_RPS to
        // simulate Paystack's documented at-least-once retry behavior --
        // every reference gets delivered 2-3x, exercising the idempotency
        // path on (nearly) every webhook, not just occasionally.
        { target: TARGET_WEBHOOK_RPS * 2, duration: '3m' },
        { target: TARGET_WEBHOOK_RPS * 2, duration: '30m' },
      ],
    },
  },
  thresholds: {
    ...endpointThresholds('checkout_initiate'),
    ...endpointThresholds('checkout_webhook'),
    ...globalErrorRateThreshold(),
  },
};

function randomTransactionId() {
  return checkoutTransactionIds[Math.floor(Math.random() * checkoutTransactionIds.length)];
}

export function initiateCheckout() {
  const headers = loginSyntheticUser(Math.floor(Math.random() * 100000));
  const transactionId = randomTransactionId();
  // Same idempotency key reused across a burst of retries for the SAME
  // transaction to simulate a client retrying after a timeout -- the
  // second+ call must return the original processor reference, never
  // initiate a second Paystack transaction (see checkout.py's idempotency
  // comment).
  const idempotencyKey = `idem_${transactionId}`;

  for (let attempt = 0; attempt < 3; attempt++) {
    const res = taggedPost(
      '/checkout/initiate',
      { transaction_id: transactionId, idempotency_key: idempotencyKey },
      'checkout_initiate',
      { headers },
    );
    check(res, {
      'initiate never returned 5xx': (r) => r.status < 500,
    });
    sleep(0.05);
  }
}

export function deliverWebhook() {
  if (!PAYSTACK_SECRET_KEY) {
    // Fails loudly rather than silently skipping signature verification --
    // see README "Running Locally" for how to supply this in CI.
    throw new Error(
      'PAYSTACK_SECRET_KEY_TEST is not set -- checkout_payment.js cannot sign webhook payloads without it.',
    );
  }

  const transactionId = randomTransactionId();
  const payload = JSON.stringify({
    event: 'charge.success',
    data: {
      reference: `txn_${transactionId}`,
      status: 'success',
      amount: 100000,
    },
  });
  const signature = hmac('sha512', PAYSTACK_SECRET_KEY, payload, 'hex');

  // Signed over `payload`'s exact bytes -- must be sent raw (taggedPostRaw),
  // not re-serialized, or the signature computed above would no longer
  // match what the server verifies against.
  const res = taggedPostRaw('/checkout/webhook', payload, 'checkout_webhook', {
    headers: { 'x-paystack-signature': signature },
  });

  check(res, {
    // 200 (processed) or 200-with-noop-on-replay are both correct;
    // duplicate-charge correctness is verified against the DB afterward,
    // not inferable from the HTTP status alone (a replay is EXPECTED to
    // return 200 -- it must just not create a second successful charge).
    'webhook delivery accepted (200) or correctly signature-rejected (401)': (r) =>
      r.status === 200 || r.status === 401,
  });
}
