// Failover (chaos) test (Test Type, README): validates the Multi-AZ and
// dependency-failure behaviors described in architecture.md actually work
// UNDER LOAD, not just at rest. This script is the "under load" half --
// steady, moderate traffic against the search + booking-hold paths, run
// concurrently with the actual fault injection, which is a separate,
// explicit operator action (not scripted here, deliberately -- killing a
// Primary Database instance or an AZ is destructive enough that it should
// never be something a load-test script does unattended).
//
// Chaos runbook (run manually, or via load_tests/seed/inject_chaos.sh,
// while this script is running against staging):
//   1. Start this script: k6 run -e BASE_URL=... failover.js
//   2. Wait 2 minutes for steady-state baseline traffic.
//   3. Inject ONE fault (never more than one at a time -- isolate the
//      signal):
//      - Kill an AZ: disable route table / detach a subnet's NAT temporarily
//        (see infra/README.md's chaos runbook section for the exact AWS CLI
//        commands against this environment's Terraform-managed resources)
//      - Kill the Primary Database instance: `aws rds reboot-db-instance
//        --db-instance-identifier staging-de-duke-primary --force-failover`
//        (forces the Multi-AZ standby promotion described in
//        infra/modules/rds_postgres)
//      - Inject artificial latency into an external dependency: toggle the
//        feature flag / env var the given service's circuit breaker reads
//        (see architecture.md "External Service Resilience") -- e.g. point
//        PAYSTACK_BASE_URL at a deliberately slow proxy for this run only.
//   4. Watch this script's live k6 output + the Observability Stack's
//      dashboards for the fault window. A PASS means: a bounded spike in
//      error rate/latency during the fault, followed by recovery to
//      baseline once failover completes (Multi-AZ) or the circuit breaker
//      opens (external dependency) -- NOT a sustained flatline of failures.
//   5. Revert the fault. Confirm recovery to baseline within the window in
//      thresholds/slo.json's global settings.
import { sleep } from 'k6';
import { taggedGet, taggedPost, loginSyntheticUser } from '../lib/client.js';
import { endpointThresholds, globalErrorRateThreshold } from '../lib/thresholds.js';

export const options = {
  scenarios: {
    failover: {
      executor: 'constant-arrival-rate',
      rate: 200, // moderate, steady load -- this test is about behavior DURING a fault, not finding a breaking point (that's stress.js's job)
      timeUnit: '1s',
      duration: '20m', // long enough to cover: baseline, fault injection, fault window, recovery
      preAllocatedVUs: 500,
      maxVUs: 1000,
    },
  },
  thresholds: {
    ...endpointThresholds('search_listings'),
    ...endpointThresholds('booking_hold_confirm'),
    // Deliberately NOT enforcing globalErrorRateThreshold() as a hard k6
    // threshold here -- a bounded error spike during the fault window is
    // the EXPECTED, correct outcome, not a failure. Pass/fail for this
    // scenario is a human/dashboard judgment call per the runbook above,
    // not an automated k6 gate.
  },
};

export default function () {
  const headers = loginSyntheticUser(Math.floor(Math.random() * 100000));
  taggedGet('/search/listings?latitude=6.5244&longitude=3.3792&radius_km=10', 'search_listings', {
    headers,
  });
  if (Math.random() < 0.05) {
    taggedPost(
      '/bookings/confirm',
      {
        listing_id: 'scaleout-probe-listing',
        check_in_date: '2026-12-05',
        check_out_date: '2026-12-06',
      },
      'booking_hold_confirm',
      { headers },
    );
  }
  sleep(0.2);
}
