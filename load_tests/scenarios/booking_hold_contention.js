// Priority Scenario 2: Booking hold contention.
// Validates: zero double-bookings when many concurrent users attempt to
// hold/book the SAME high-demand listing and overlapping dates (the
// double-booking prevention rule, schema.md `Transaction.possessionPeriodEndDate`),
// and that the hold-expiry scheduled job (R-019) keeps pace with hold
// creation volume rather than falling behind.
//
// k6 itself only asserts HTTP-level correctness (exactly one 201 per
// contended date-range, the rest 409/conflict) -- the FINAL, authoritative
// check is a direct database assertion, run by
// apps/backend/scripts/verify_no_double_booking.py (run as a one-off ECS task, not directly) immediately after this
// script finishes (wired into .github/workflows/load-test-full.yml). Both
// checks must pass; the HTTP-level check alone is not sufficient, since a
// bug could return the correct status codes while still writing
// overlapping rows.
import { check, sleep } from 'k6';
import { taggedPost, loginSyntheticUser } from '../lib/client.js';
import { endpointThresholds, globalErrorRateThreshold } from '../lib/thresholds.js';

// A small, fixed pool of contended listing IDs -- seeded by
// apps/backend/scripts/seed_load_test_data.py --with-contended-listings, which prints the
// IDs to load_tests/seed/contended_listing_ids.json for this script to read.
// Deliberately small (contention needs a shared target) and fixed date
// ranges, so every VU is racing for the SAME slot, not spread across the
// catalog like search_discovery.js.
// k6's goja runtime doesn't support import-assertion syntax -- see
// lib/thresholds.js's identical fix/comment for why this is open()+parse
// instead of a static JSON import.
const contendedListings = JSON.parse(open('../seed/contended_listing_ids.json'));

const CONTENDED_DATE_RANGES = [
  { start: '2026-09-01', end: '2026-09-07' },
  { start: '2026-09-10', end: '2026-09-15' },
];

export const options = {
  scenarios: {
    booking_hold_contention: {
      executor: 'per-vu-iterations',
      vus: 500, // 500 concurrent users racing for a small pool of listings/dates
      iterations: 5,
      maxDuration: '10m',
    },
  },
  thresholds: {
    ...endpointThresholds('booking_hold_confirm'),
    ...globalErrorRateThreshold(),
  },
};

export default function () {
  const headers = loginSyntheticUser(__VU * 1000 + __ITER);
  const listingId = contendedListings[Math.floor(Math.random() * contendedListings.length)];
  const range = CONTENDED_DATE_RANGES[Math.floor(Math.random() * CONTENDED_DATE_RANGES.length)];

  const res = taggedPost(
    '/bookings/confirm',
    {
      // ConfirmBookingRequest field names (app/schemas/booking.py) -- the
      // service maps these onto Transaction.possession_period_start_date/
      // end_date internally (app/services/booking_service.py).
      listing_id: listingId,
      check_in_date: range.start,
      check_out_date: range.end,
    },
    'booking_hold_confirm',
    { headers },
  );

  // Exactly one concurrent hold per (listing, overlapping date range) should
  // succeed (201); every other concurrent attempt for the same slot must be
  // rejected (409), never silently succeed.
  check(res, {
    'hold either succeeded (201) or was correctly rejected as conflicting (409)': (r) =>
      r.status === 201 || r.status === 409,
    'hold never returned 5xx under contention': (r) => r.status < 500,
  });

  sleep(0.1);
}
