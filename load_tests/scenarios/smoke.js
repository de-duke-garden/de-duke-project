// Lightweight performance smoke test -- run on EVERY backend deploy (see
// .github/workflows/backend-deploy.yml's "Performance smoke test" step),
// not a full gate run. Purpose: catch an obvious latency/error-rate
// regression in ~2-3 minutes, using a tiny fraction of a real scenario's
// load. This is NOT a substitute for the full suite's launch-gate run --
// see load_tests/README.md Cadence.
import { sleep } from 'k6';
import { taggedGet, loginSyntheticUser } from '../lib/client.js';
import { endpointThresholds, globalErrorRateThreshold } from '../lib/thresholds.js';

export const options = {
  vus: 20,
  duration: '2m',
  thresholds: {
    ...endpointThresholds('search_listings'),
    ...endpointThresholds('auth_login'),
    ...globalErrorRateThreshold(),
  },
};

export default function () {
  // A single representative read path (search) plus an auth round-trip --
  // enough to catch "the new image broke the DB connection" or "this
  // deploy tripled p95 latency" without running the full scenario suite.
  const headers = loginSyntheticUser(Math.floor(Math.random() * 1000));
  taggedGet(
    '/search/listings?latitude=6.5244&longitude=3.3792&radius_km=10',
    'search_listings',
    { headers },
  );
  sleep(1);
}
