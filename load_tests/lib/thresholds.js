// Shared threshold loader -- every k6 scenario script imports this so
// pass/fail criteria live in one place (thresholds/slo.json) instead of
// being duplicated/drifting across scenario files. See load_tests/README.md
// "Pass/Fail Criteria".
// k6's JS runtime (goja) does not support ES import-assertion syntax
// (`assert { type: 'json' }`) -- confirmed via a real k6 run against this
// file, which failed with "Unexpected token {". k6's own documented
// pattern for reading a local JSON file at init time is `open()` +
// `JSON.parse()` instead.
const slo = JSON.parse(open('../thresholds/slo.json'));

/**
 * Builds a k6 `thresholds` block for a named endpoint's metrics
 * (`http_req_duration{endpoint:<name>}` and the shared error-rate metric),
 * pulling p95/p99 targets from thresholds/slo.json so every scenario stays
 * consistent with the documented SLOs.
 *
 * @param {string} endpointKey - key into slo.json's `endpoints` map
 * @returns {object} k6 `thresholds` fragment, spread into a scenario's `options.thresholds`
 */
export function endpointThresholds(endpointKey) {
  const spec = slo.endpoints[endpointKey];
  if (!spec) {
    throw new Error(
      `load_tests/thresholds/slo.json has no entry for endpoint "${endpointKey}" -- add one before referencing it from a scenario script.`,
    );
  }
  return {
    [`http_req_duration{endpoint:${endpointKey}}`]: [
      `p(95)<${spec.p95_ms}`,
      `p(99)<${spec.p99_ms}`,
    ],
  };
}

/** Global error-rate threshold applied across every scenario (README "Error rate stays below 0.1%"). */
export function globalErrorRateThreshold() {
  return { http_req_failed: [`rate<${slo.global.error_rate_max}`] };
}

export const GLOBAL_SLO = slo.global;
