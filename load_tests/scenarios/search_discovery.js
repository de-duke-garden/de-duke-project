// Priority Scenario 1: Search & Discovery under load.
// Validates: read replica routing, Caching Layer hit ratio for hot
// queries/embeddings, and that the embedding-generation timeout/fallback
// (FEAT-031) actually triggers correctly when the embedding dependency is
// slow -- see docs/De-Duke/architecture.md "External Service Resilience"
// (circuit breaker -> degraded keyword-only search).
import { sleep } from 'k6';
import { taggedGet, loginSyntheticUser } from '../lib/client.js';
import { endpointThresholds, globalErrorRateThreshold } from '../lib/thresholds.js';

// Target: 800 combined geo+semantic searches/sec sustained (README Target Scale).
// RAMP_BEYOND_TARGET / DURATION let this same script serve Load, Stress, and
// Soak runs per README's Test Types table without duplicating scenarios.
const TARGET_RPS = 800;
const STRESS = __ENV.RAMP_BEYOND_TARGET === 'true';
const DURATION = __ENV.DURATION || '45m';

export const options = {
  scenarios: {
    search_discovery: {
      executor: 'ramping-arrival-rate',
      startRate: 50,
      timeUnit: '1s',
      preAllocatedVUs: 500,
      maxVUs: STRESS ? 4000 : 1500,
      stages: STRESS
        ? [
            { target: TARGET_RPS, duration: '5m' },
            { target: TARGET_RPS * 3, duration: '15m' }, // ramp well past target to find the breaking point
            { target: TARGET_RPS * 3, duration: '10m' }, // hold at breaking point, observe failure mode
          ]
        : [
            { target: TARGET_RPS, duration: '5m' }, // ramp to target
            { target: TARGET_RPS, duration: DURATION }, // sustain at target
          ],
    },
  },
  thresholds: {
    ...endpointThresholds('search_listings'),
    ...globalErrorRateThreshold(),
  },
};

// Hot-query simulation: a small pool of popular coordinates/keywords gets
// requested disproportionately (Zipf-ish), so the Caching Layer's hit ratio
// is actually exercised rather than every request being a unique cold miss.
const HOT_LOCATIONS = [
  { lat: 6.5244, lng: 3.3792, label: 'Lagos Island' }, // hot
  { lat: 6.4531, lng: 3.3958, label: 'Lekki' }, // hot
  { lat: 9.0765, lng: 7.3986, label: 'Abuja Central' }, // hot
];
const HOT_QUERIES = ['3 bedroom flat', 'shortlet with pool', 'office space lekki'];

function randomHotOrColdLocation() {
  // 70% of traffic hits the hot set (cache-friendly), 30% is a random
  // cold-miss coordinate within Nigeria's rough bounding box.
  if (Math.random() < 0.7) {
    return HOT_LOCATIONS[Math.floor(Math.random() * HOT_LOCATIONS.length)];
  }
  return {
    lat: 4 + Math.random() * 9, // ~4-13N covers Nigeria
    lng: 3 + Math.random() * 11, // ~3-14E covers Nigeria
    label: 'cold',
  };
}

export default function () {
  const headers = loginSyntheticUser(Math.floor(Math.random() * 100000));
  const loc = randomHotOrColdLocation();
  const useSemanticQuery = Math.random() < 0.4; // 40% of searches are free-text (semantic), rest are pure geo+filter
  const query = useSemanticQuery
    ? HOT_QUERIES[Math.floor(Math.random() * HOT_QUERIES.length)]
    : null;

  const params = new URLSearchParams({
    latitude: String(loc.lat),
    longitude: String(loc.lng),
    radius_km: '10',
    sort_by: 'newest',
  });
  if (query) params.set('query', query);

  taggedGet(`/search/listings?${params.toString()}`, 'search_listings', { headers });
  sleep(Math.random() * 0.5); // think time between result-page views
}
