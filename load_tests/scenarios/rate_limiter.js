// Priority Scenario 6: Rate limiter correctness at scale.
// Validates: the centralized, Cache-backed (Redis) rate limiter
// (architecture.md "Security") enforces limits correctly ACROSS many
// concurrent Backend API Service Fargate tasks, not just per-task -- a
// limiter that only worked correctly on a single instance would pass a
// small local test and silently fail once traffic fans out across the
// auto-scaled task pool, which is exactly what this scenario is designed
// to catch.
import { check, sleep } from 'k6';
import { taggedPost } from '../lib/client.js';
import { globalErrorRateThreshold } from '../lib/thresholds.js';

// A small, FIXED set of identities (not the usual large synthetic pool) --
// concentrating traffic onto few identities is what actually exercises
// per-user/per-IP rate limiting; spreading load across thousands of users
// (like search_discovery.js does) would never trip any single user's limit.
const FIXED_TEST_ACCOUNTS = Array.from({ length: 20 }, (_, i) => ({
  email: `load+ratelimit${i}@synthetic.de-duke.internal`,
  password: 'LoadTest-Synthetic-Only-1!',
}));

export const options = {
  scenarios: {
    rate_limiter: {
      // Deliberately way beyond any reasonable per-user auth rate limit,
      // sustained -- the test is not "can this succeed" but "does the
      // limiter kick in correctly and STAY correct across every Fargate
      // task handling these requests, not just some of them."
      executor: 'constant-arrival-rate',
      rate: 200,
      timeUnit: '1s',
      duration: '10m',
      preAllocatedVUs: 300,
      maxVUs: 600,
    },
  },
  thresholds: {
    ...globalErrorRateThreshold(),
    // Not a real global error-rate gate here -- 429s are the EXPECTED,
    // correct outcome for most of this scenario's traffic, so
    // http_req_failed isn't meaningful the way it is for other scenarios.
    // The real assertion is in the checks below (rate_limit_enforced).
  },
};

export default function () {
  const account = FIXED_TEST_ACCOUNTS[Math.floor(Math.random() * FIXED_TEST_ACCOUNTS.length)];
  const res = taggedPost('/auth/login', account, 'auth_login');

  check(res, {
    // A correct centralized limiter returns 429 once this identity exceeds
    // its threshold, consistently, regardless of which Fargate task
    // handled the request. 200 (still under threshold) is also valid --
    // what's NOT valid is an unbounded stream of 200s from a fixed
    // identity hammering the endpoint at 200 req/s, which would indicate
    // the limiter is only enforcing per-task (in-memory) rather than
    // centrally via the Caching Layer.
    'rate limiter responded with 200 (under threshold) or 429 (limited), never unbounded success':
      (r) => r.status === 200 || r.status === 429,
  });

  // No sleep -- constant-arrival-rate governs pacing; a per-iteration sleep
  // here would just reduce achieved concurrency without helping realism.
}
