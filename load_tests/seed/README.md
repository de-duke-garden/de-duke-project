# Seed outputs

`contended_listing_ids.json`, `viral_listing_id.json`, and
`checkout_transaction_ids.json` are checked in as empty placeholders so the
k6 scenario scripts' `JSON.parse(open('../seed/....json'))` calls (k6's
goja runtime doesn't support ES import-assertion syntax, confirmed via a
real k6 run) resolve on a fresh checkout, before the seeder has ever run.

The actual seeder is `apps/backend/scripts/seed_load_test_data.py` -- NOT
in this directory. It lives with the backend app because it reuses the
app's own database connection setup and can only run as a one-off ECS
Fargate task inside the VPC (see that script's docstring, and
`load_tests/README.md`'s "Environment & Data" section, for why). Since a
one-off task has no way to write files back to this directory directly, it
prints its seed output as `SEED_OUTPUT_JSON::` marker lines to stdout,
which `.github/workflows/load-test-full.yml`'s `seed` job reads back out of
CloudWatch Logs afterward and writes into this directory before every
scenario run.

**Always run via the `load-test-full.yml` workflow (or the equivalent `aws
ecs run-task` invocation in `load_tests/README.md`) before a real scenario
run** -- the placeholders alone are not usable fixtures (empty pools mean
every scenario that depends on them, e.g. `booking_hold_contention.js`,
will divide by zero / index into an empty array immediately).
