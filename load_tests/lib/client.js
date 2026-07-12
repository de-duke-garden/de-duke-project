// Shared k6 HTTP client helpers -- base URL resolution, auth, and a small
// wrapper that tags every request with `endpoint` so lib/thresholds.js's
// per-endpoint thresholds (http_req_duration{endpoint:...}) actually match
// something. Every scenario script should go through `taggedGet`/`taggedPost`
// rather than calling http.get/http.post directly, so tagging stays
// consistent across the suite.
import http from 'k6/http';
import { check } from 'k6';

// BASE_URL is passed via `-e BASE_URL=...` (see README "Running Locally") or,
// in CI, injected by .github/workflows/backend-deploy.yml / load-test-full.yml
// from that run's Terraform `alb_dns_name` output.
export const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
export const API_PREFIX = '/v1';

/**
 * GET wrapped with the endpoint tag used by per-endpoint thresholds.
 * @param {string} path - path under API_PREFIX, e.g. "/search/listings"
 * @param {string} endpointTag - key matching thresholds/slo.json's `endpoints`
 * @param {object} [params] - k6 http params (headers, etc.), merged with the tag
 */
export function taggedGet(path, endpointTag, params = {}) {
  return http.get(`${BASE_URL}${API_PREFIX}${path}`, {
    ...params,
    tags: { ...(params.tags || {}), endpoint: endpointTag },
  });
}

/** POST wrapped with the endpoint tag used by per-endpoint thresholds. */
export function taggedPost(path, body, endpointTag, params = {}) {
  return http.post(`${BASE_URL}${API_PREFIX}${path}`, JSON.stringify(body), {
    ...params,
    headers: { 'Content-Type': 'application/json', ...(params.headers || {}) },
    tags: { ...(params.tags || {}), endpoint: endpointTag },
  });
}

/**
 * POST with a pre-serialized raw string body, sent byte-for-byte as given
 * -- required whenever the caller needs the response body's exact bytes to
 * match something computed beforehand (e.g. checkout_payment.js signing a
 * webhook payload with HMAC before sending it: re-serializing the body via
 * JSON.stringify a second time is not guaranteed to reproduce identical
 * bytes/key-ordering, which would invalidate the signature).
 */
export function taggedPostRaw(path, rawBody, endpointTag, params = {}) {
  return http.post(`${BASE_URL}${API_PREFIX}${path}`, rawBody, {
    ...params,
    headers: { 'Content-Type': 'application/json', ...(params.headers || {}) },
    tags: { ...(params.tags || {}), endpoint: endpointTag },
  });
}

/**
 * Logs in a seeded synthetic user (see apps/backend/scripts/seed_load_test_data.py, which
 * creates a deterministic block of load-test-only accounts at
 * load+<n>@synthetic.de-duke.internal / a fixed test password) and returns
 * an Authorization header ready to spread into a request's `headers`.
 * Synthetic accounts only -- never runs against real user data, and the
 * seed script refuses to run against anything but staging (see README).
 */
export function loginSyntheticUser(userIndex) {
  return _loginSynthetic(`load+${userIndex}@synthetic.de-duke.internal`);
}

/**
 * Logs in a seeded synthetic VERIFIED HOST account -- a distinct email
 * namespace (`load+host<n>@...`) from loginSyntheticUser's regular seeker
 * pool. Found via a real staging run: seed_load_test_data.py originally
 * had verified hosts and regular users sharing the same `load+<n>@...`
 * index space, which collided on email's unique index the moment both
 * seeded index 0 -- see that script's seed_verified_hosts comment.
 * listing_creation.js (the only scenario needing a verified host, since
 * listing creation requires one) must use this, not loginSyntheticUser.
 */
export function loginSyntheticHost(hostIndex) {
  return _loginSynthetic(`load+host${hostIndex}@synthetic.de-duke.internal`);
}

function _loginSynthetic(email) {
  const res = taggedPost(
    '/auth/login',
    { email, password: 'LoadTest-Synthetic-Only-1!' },
    'auth_login',
  );
  check(res, { 'login succeeded': (r) => r.status === 200 });
  const token = res.status === 200 ? res.json('access_token') : null;
  return token ? { Authorization: `Bearer ${token}` } : {};
}
