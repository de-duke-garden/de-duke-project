// Spike test (Test Type, README): validates auto-scaling reacts fast
// enough to a sudden, sharp traffic increase -- the "viral listing"
// scenario. Reuses search_discovery's realistic traffic shape rather than
// duplicating request logic, but with a spike-specific stage profile: 10x
// traffic within 1 minute, then holds, per architecture.md's Spike test
// definition.
import { sleep } from 'k6';
import { taggedGet, loginSyntheticUser } from '../lib/client.js';
import { endpointThresholds, globalErrorRateThreshold } from '../lib/thresholds.js';
import { GLOBAL_SLO } from '../lib/thresholds.js';

const BASELINE_RPS = 80;
const SPIKE_RPS = BASELINE_RPS * 10; // 10x within 1 minute, per architecture.md's Spike test definition

export const options = {
  scenarios: {
    spike: {
      executor: 'ramping-arrival-rate',
      startRate: BASELINE_RPS,
      timeUnit: '1s',
      preAllocatedVUs: 500,
      maxVUs: 3000,
      stages: [
        { target: BASELINE_RPS, duration: '3m' }, // steady baseline
        { target: SPIKE_RPS, duration: '1m' }, // the spike: viral listing
        { target: SPIKE_RPS, duration: '10m' }, // hold -- confirms auto-scaling actually stabilizes, not just survives the initial burst
        { target: BASELINE_RPS, duration: '3m' }, // recovery -- confirms scale-in and that no backlog/leak was left behind
      ],
    },
  },
  thresholds: {
    ...endpointThresholds('search_listings'),
    ...globalErrorRateThreshold(),
  },
};

// A single "viral listing" ID all spike traffic converges on -- seeded by
// apps/backend/scripts/seed_load_test_data.py --with-viral-listing, which prints the ID to
// seed/viral_listing_id.json.
// k6's goja runtime doesn't support import-assertion syntax -- see
// lib/thresholds.js's identical fix/comment.
const viralListing = JSON.parse(open('../seed/viral_listing_id.json'));

export default function () {
  const headers = loginSyntheticUser(Math.floor(Math.random() * 100000));
  taggedGet(`/listings/${viralListing.id}`, 'search_listings', { headers });
  sleep(0.1);
}

// Auto-scaling stabilization time is read from CloudWatch (target-tracking
// scaling policy's actual react time) by
// .github/workflows/load-test-full.yml's post-run step, checked against
// GLOBAL_SLO.auto_scale_stabilize_seconds_max (thresholds/slo.json) -- k6
// itself has no visibility into ECS service scaling events, only the
// client-observable latency/error-rate symptoms asserted above.
export { GLOBAL_SLO };
