// Priority Scenario 7: Fargate scale-out under the Connection Pooler.
// Validates: rapid auto-scale-out (matching the Spike test's shape) stays
// within the Database Connection Pooler's configured ceiling -- i.e. the
// Primary Database's connection limit is never at risk regardless of how
// many API tasks spin up in response to this traffic. This script drives
// the load; the actual pass/fail signal is read from CloudWatch/Terraform
// outputs by .github/workflows/load-test-full.yml's "Check connection pool
// saturation" step (RDS Proxy's ClientConnections / DatabaseConnections
// metrics against modules/rds_postgres's pooler ceiling), not from k6
// itself -- k6 has no visibility into RDS Proxy's internal connection
// accounting.
import { sleep } from 'k6';
import { taggedGet, taggedPost, loginSyntheticUser } from '../lib/client.js';
import { endpointThresholds, globalErrorRateThreshold } from '../lib/thresholds.js';

export const options = {
  scenarios: {
    fargate_scaleout: {
      executor: 'ramping-arrival-rate',
      startRate: 50,
      timeUnit: '1s',
      preAllocatedVUs: 1000,
      maxVUs: 6000,
      stages: [
        { target: 50, duration: '2m' }, // baseline, steady-state task count
        { target: 3000, duration: '1m' }, // sharp spike: 60x within 1 minute -- forces rapid scale-out
        { target: 3000, duration: '10m' }, // hold at spike level -- new tasks fully ramped, hitting DB via RDS Proxy
        { target: 50, duration: '3m' }, // scale back down -- confirms tasks (and their pooled connections) actually release
      ],
    },
  },
  thresholds: {
    ...endpointThresholds('search_listings'),
    ...endpointThresholds('booking_hold_confirm'),
    ...globalErrorRateThreshold(),
  },
};

export default function () {
  // Mixed read (search, cheap) + write (booking hold, opens a real DB
  // transaction) traffic -- a pure read spike wouldn't meaningfully
  // pressure-test connection pooling the way DB writes across many
  // concurrently-scaling tasks does.
  const headers = loginSyntheticUser(Math.floor(Math.random() * 100000));
  taggedGet('/search/listings?latitude=6.5244&longitude=3.3792&radius_km=10', 'search_listings', {
    headers,
  });

  if (Math.random() < 0.1) {
    taggedPost(
      '/bookings/confirm',
      {
        listing_id: 'scaleout-probe-listing', // see seed script's --with-scaleout-probe-listing (high availability window, low real contention -- this scenario is about connection volume, not booking-hold correctness, which is Scenario 2's job)
        check_in_date: '2026-12-01',
        check_out_date: '2026-12-02',
      },
      'booking_hold_confirm',
      { headers },
    );
  }

  sleep(0.2);
}
