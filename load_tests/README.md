# De-Duke -- Load Testing & Performance Validation

Implements `docs/De-Duke/architecture.md`'s "Load Testing & Performance
Validation" section and the hard Launch Gate defined in `docs/De-Duke/roadmap.md`
Phase 1: **public launch does not proceed until this suite passes at target
scale, with zero double-bookings and zero duplicate charges under
concurrency.** This is not a target to aim for -- it is a pass/fail gate.

Runs exclusively against the `staging` environment (`infra/environments/staging`),
which is provisioned identically to `production` (same instance types, replica
counts, auto-scaling config) specifically so results here are representative.
Never run this against `production`.

## Target Scale (initial working numbers)

These are the team's first concrete numbers, per architecture.md's
requirement that targets be "defined, refined as real usage data becomes
available, but never left undefined." **Business/ops should review and
adjust these before the Phase 1 launch gate run** -- they were derived from
the roadmap's "millions of users" framing and typical marketplace launch
patterns, not real traffic data (none exists pre-launch).

| Metric | Target | Basis |
|---|---|---|
| Concurrent active users (peak) | 50,000 | ~1% of a 5M-user long-term target concurrently active at peak (evening hours, NGN) |
| Peak requests/sec, Backend API | 2,000 req/s | ~5 requests/user/session across a peak window, spread over 50k concurrent users |
| Peak searches/sec (geo + semantic combined) | 800 search/s | Search is the highest-frequency action in `user_flow.md`'s core loop |
| Peak concurrent chat conversations | 15,000 | ~30% of concurrent users mid-conversation at peak |
| Peak chat messages/sec | 300 msg/s | Firestore-side, simulated separately from HTTP load (see Tooling) |
| Peak checkout attempts/sec | 50 checkout/s | Conversion funnel narrows sharply from search -> checkout |
| Peak Paystack webhook deliveries/sec | 50 webhook/s | 1:1 with checkout attempts, plus deliberately injected duplicate/replayed deliveries per Scenario 3 |
| Listing catalog size (seeded) | 5,000,000 listings | Matches the roadmap's explicit "index and query-planner behavior on 50 listings is not representative of behavior on 5 million" framing |
| Seeded users | 2,000,000 | Proportional to catalog size and target concurrency |
| Seeded historical transactions | 500,000 | For transaction-history/receipts query load and realistic DB size |

Thresholds derived from these targets live in `thresholds/slo.json` and are
consumed by every scenario script via `lib/thresholds.js`.

## Test Types

| Type | Script | Duration | Purpose |
|---|---|---|---|
| Load | `scenarios/*.js` run with `--tag test_type=load` | 30-60 min sustained | Confirm target latency/error-rate thresholds hold at expected peak, sustained |
| Stress | same scripts, `k6 run -e RAMP_BEYOND_TARGET=true` | until failure threshold crossed | Find the actual breaking point; confirm graceful (not catastrophic) degradation |
| Soak | same scripts, `-e DURATION=8h` | 4-8+ hours | Catch slow leaks / resource exhaustion invisible on a short run |
| Spike | `scenarios/spike.js` | traffic 10x within 1 min, then holds | Validate auto-scaling reacts fast enough (e.g. a "viral listing") |
| Failover (chaos) | `scenarios/failover.js` + manual AZ/instance kill per runbook below | run concurrently with Load | Validate Multi-AZ/dependency-failure behavior actually works under load |

## Priority Scenarios

| # | Script | Validates |
|---|---|---|
| 1 | `scenarios/search_discovery.js` | Read replica routing, Caching Layer hit ratio, embedding-timeout fallback (FEAT-031 degrades to keyword-only search under injected latency) |
| 2 | `scenarios/booking_hold_contention.js` | Zero double-bookings under concurrent holds on the same listing/dates (schema.md `Transaction.possessionPeriodEndDate`); hold-expiry job (R-019) keeps pace |
| 3 | `scenarios/checkout_payment.js` | Idempotency-key + webhook-signature-verification hold under concurrency, including deliberately duplicated/replayed Paystack webhooks -- zero duplicate charges |
| 4 | `scenarios/listing_creation.js` | Structured multi-image/multi-room upload contract under concurrent hosts publishing; embedding (re)generation backlog stays bounded |
| 5 | `scenarios/chat_volume.js` | Firestore performance/cost at volume, including Admin Web Console cross-conversation queries (simulated separately -- see Tooling) |
| 6 | `scenarios/rate_limiter.js` | Cache-backed centralized rate limiter enforces correctly across many concurrent Fargate tasks, not per-task |
| 7 | `scenarios/fargate_scaleout.js` | Auto-scale-out under the Spike profile stays within the Database Connection Pooler's configured ceiling |
| -- | `scenarios/smoke.js` | Lightweight (~2-3 min) subset of the above, run on every backend deploy (see `.github/workflows/backend-deploy.yml`'s Performance smoke test step) -- not a gate test, a regression tripwire |

## Environment & Data

Staging only, seeded via `apps/backend/scripts/seed_load_test_data.py` at
the volumes in the Target Scale table above. That script lives in
`apps/backend/scripts/`, not here -- it reuses the backend app's own
`database_url` assembly (`DB_PROXY_ENDPOINT` + Secrets Manager, see
`app/core/config.py`) and can therefore only run from INSIDE the VPC, as a
one-off ECS Fargate task (same pattern `backend-deploy.yml`'s migration
step uses), never as a plain step on a GitHub-hosted runner -- those have
no network path to the private-subnet RDS Proxy. `.github/workflows/load-test-full.yml`'s
`seed` job does exactly this: runs the script as a one-off task, then reads
its seed-output JSON back out of CloudWatch Logs (see the script's
`SEED_OUTPUT_MARKER` comment) and writes it into `load_tests/seed/*.json`
for the k6 scenario scripts to `import`.

Seeding is idempotent and safe to re-run (truncates and reseeds only rows
identified by the `@synthetic.de-duke.internal` email suffix) and refuses
to run against anything but staging (checked via `DB_PROXY_ENDPOINT`'s
prefix, which ECS sets per-environment -- there is no way to accidentally
point it at production).

To run it manually (e.g. outside the CI workflow, still via `aws ecs
run-task` against staging -- never by connecting directly, since that
network path doesn't exist from outside the VPC):

```bash
aws ecs run-task \
  --cluster staging-de-duke-cluster \
  --task-definition staging-de-duke-api \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[...],securityGroups=[...],assignPublicIp=DISABLED}" \
  --overrides '{"containerOverrides":[{"name":"backend-api","command":["python","scripts/seed_load_test_data.py","--listings","5000000","--users","2000000","--transactions","500000"]}]}'
```

## Tooling

[k6](https://k6.io) for all HTTP API load (scenarios 1-4, 6-7), run in
distributed cloud mode across multiple regions (`k6 cloud run` or
self-hosted k6 operator across >1 AWS region) so the load generator itself
is never the bottleneck being measured -- never run these from a single
local machine for a real gate run (local runs are fine for iterating on a
script).

Chat/Firestore load (scenario 5) is **not** k6 -- it's simulated with a
separate Node.js load-generator (`scenarios/chat_volume.js` is actually a
Node script driving the Firebase Admin SDK directly against Firestore, not
a k6 HTTP script) since it exercises direct client-to-Firestore traffic, a
fundamentally different path than the Backend API Service.

## Pass/Fail Criteria

A run is a pass only if, at target scale (enforced by `lib/thresholds.js`
against `thresholds/slo.json`):

- p95 latency for search, chat-token-issuance, and checkout endpoints stays within the defined per-endpoint thresholds
- Error rate stays below 0.1% (outside deliberately-injected failure scenarios)
- Auto-scaling stabilizes within 3 minutes of a spike
- No unbounded Task Queue growth (SQS queue depth returns to baseline within 5 min of load subsiding)
- No database connection pool saturation; read replica lag stays under 2s
- **Zero double-bookings and zero duplicate charges across every concurrency scenario -- hard gate, not tunable.** `scenarios/booking_hold_contention.js` and `scenarios/checkout_payment.js` assert this directly against the database at the end of each run, not just via HTTP response codes.

## Cadence

- **Before Phase 1 public launch:** full suite (all test types, all scenarios) against target scale -- the launch gate. Do not launch without a passing run recorded.
- **Before each subsequent roadmap phase:** re-run in full against updated targets.
- **Every backend deploy:** `scenarios/smoke.js` only, wired into `.github/workflows/backend-deploy.yml`'s `deploy` job -- a failure triggers the same rollback as the functional smoke test.
- **Recurring full-scale run:** quarterly, or triggered manually once real production traffic approaches these targets -- see `.github/workflows/load-test-full.yml`.

## Running Locally

```bash
# One-off scenario, iterating on a script (small VU count, short duration):
k6 run --vus 10 --duration 30s -e BASE_URL=https://staging.api.de-duke.example load_tests/scenarios/search_discovery.js

# Full scenario at target scale -- only from the distributed/cloud runner,
# per Tooling above, and only against staging:
k6 run -e BASE_URL=https://staging.api.de-duke.example -e K6_ENVIRONMENT=staging load_tests/scenarios/search_discovery.js
```

See `.github/workflows/load-test-full.yml` for the CI-driven full-suite run (manually triggered + scheduled quarterly).
