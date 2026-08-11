# De-Duke GCP Infrastructure (Proposal — for review)

> **Status:** APPROVED — scaffolding complete (`infra/gcp/`). **Not yet
> applied.** The Terraform tree is written and validated; `terraform apply`
> is the explicit next gate.
>
> **Source of truth:** `docs/De-Duke/architecture.md` (product architecture).
> This document is the migration proposal + build reference for the
> AWS-hosted platform described there. It complements, and does not replace,
> the AWS Terraform in `infra/`.

## 1. Goal

Migrate De-Duke's AWS-hosted backend platform (compute, database, cache, queue,
media storage, secrets, registry, DNS records) to Google Cloud, and cut the
pre-launch infrastructure bill in the process. The Firebase/Firestore side
already runs on GCP in the **`de-duke-services`** project; this migration
consolidates the whole platform into that same project.

**Decisions already made (confirmed with the operator):**
- New GCP Terraform lives in a **new `infra/gcp/` directory** with its own
  remote state — the AWS tree (`infra/`) is left untouched and live until
  cutover.
- GCP target project: **`de-duke-services`** (verified live: Firestore,
  Firebase Auth, FCM, Maps, Gemini already enabled there; no compute/buckets/
  Pub/Sub topics/DNS zones exist yet).
- Media: **GCS + Cloud CDN** (direct S3 + CloudFront replacement).
- Queue: **Pub/Sub + Cloud Run job worker** (direct SQS + Fargate worker
  replacement).
- DNS: **Cloud DNS** zone for `de-duke.com`; registrar nameservers repointed
  to Cloud DNS at cutover.
- State backend: **GCS bucket in the GCP project** (`de-duke-services`).
- Cutover: **parallel** — GCP built and verified while AWS stays live; DNS
  repointed; then AWS production `terraform destroy`ed.
- Deferred (not built now): Cloud Load Balancer + Cloud Armor, Memorystore for
  Redis, separate staging environment, NAT gateways, connection pooler.

## 2. Current AWS inventory (what exists and what it costs)

Live environment: **production only** (development and staging destroyed).
All in `eu-west-1`, account suffix `145168165862`.

| AWS resource | Sizing | Est. monthly cost |
|---|---|---|
| Fargate API tasks (always-on floor) | 4 × 1 vCPU / 2 GB | ~$140 |
| NAT gateways × 2 (+ EIPs) | per-AZ | ~$65 |
| ALB (+ LCU) | internet-facing | ~$17 |
| RDS PostgreSQL | `db.t4g.micro`, 20 GB, single-AZ | ~$16 |
| ElastiCache Redis | `cache.t4g.micro` | ~$13 |
| RDS Proxy | POSTGRESQL | ~$8 |
| WAFv2 + CloudFront + S3 + SQS + Secrets + ECR + CloudWatch | baseline | ~$15–20 |
| **Total** | | **~$275–290/mo** |

The big-ticket items are all "running at scale before there is scale":
the 4-task Fargate floor, the NAT gateways, and the dedicated Redis/proxy/WAF
for near-zero traffic.

## 3. Target GCP architecture (minimal, launch-scoped)

| Concern | AWS today | GCP target |
|---|---|---|
| API compute | Fargate service (4 tasks min) | **Cloud Run service**, scale-to-zero |
| Worker | Fargate worker pool | **Cloud Run service** (Pub/Sub push-triggered) |
| Primary DB | RDS Postgres + PostGIS/pgvector | **Cloud SQL for PostgreSQL** (PostGIS + pgvector supported), small shared-core tier |
| Task queue | SQS + DLQ | **Pub/Sub** topic + push subscription (retry/DLQ policy) |
| Media storage | S3 | **GCS bucket** |
| Media CDN | CloudFront | **Cloud CDN** (backend bucket on the HTTPS LB) |
| TLS + routing | ALB | **Global HTTPS Load Balancer** (host-based: api → Cloud Run, cdn → media bucket) |
| Secrets | Secrets Manager | **Secret Manager** |
| Container registry | ECR | **Artifact Registry** |
| DNS records | Route53 subdomains in de-duke.com zone | **Cloud DNS** zone for de-duke.com |
| WAF | WAFv2 (ALB-attached) | **Deferred** — Cloud Armor attaches to the same LB later |
| Cache | ElastiCache Redis | **Deferred** — Memorystore only when search/rate-limiting needs it |
| Connection pooler | RDS Proxy | **Replaced** — Cloud SQL Auth Proxy sidecar on 127.0.0.1:5432 |
| NAT/egress | NAT gateways | **Not needed** — Cloud Run has native outbound egress |
| Recurring jobs | hold-expiry worker sweep | **Cloud Scheduler** → Pub/Sub → worker |

**Important correction vs. the earlier proposal:** Cloud CDN on GCP *requires*
a global HTTPS load balancer (a backend bucket cannot be served without one),
so the LB is **in scope** — the deferred piece is only Cloud Armor (WAF),
which attaches to the same LB later at zero re-architecture cost.

**Explicitly removed for launch (billed today, not needed):**
- Fargate 4-task floor → scale-to-zero Cloud Run (~$140/mo → ~$0 idle)
- 2 NAT gateways (~$65/mo)
- RDS Proxy, dedicated ElastiCache, WAF
- Staging environment (not rebuilt on GCP)
- Amazon SES email — decision pending at cutover (SES is API-only; can be
  replaced by a GCP-neutral provider like Resend/Postmark, or kept)

## 4. Cost estimate — GCP target

| GCP resource | Tier | Est. monthly |
|---|---|---|
| Cloud Run (API + worker) | scale-to-zero | ~$0–5 (idle $0) |
| Cloud SQL PostgreSQL | `db-g1-small` + 20 GB | ~$25 |
| Global HTTPS LB + static IP + managed cert | 1 forwarding rule | ~$18 |
| GCS + Cloud CDN egress | low volume | ~$1–5 |
| Pub/Sub + Scheduler | low volume | ~$0–1 |
| Secret Manager + Artifact Registry + Cloud DNS + Cloud Logging | baseline | ~$1–3 |
| **Total** | | **~$45–55/mo** |

> Numbers are estimates from public list pricing; confirm exact figures in the
> Google Cloud Pricing Calculator before apply. The two dominant costs are
> Cloud SQL (~$25) and the mandatory HTTPS LB (~$18). Dropping the LB would
> mean dropping Cloud CDN too (GCS-only media, direct signed-URL access) —
> the tradeoff was raised and CDN kept. If latency to the primary user base
> allows a US region, the Cloud SQL free tier (`db-f1-micro`/`db-g1-small`)
> removes the database line entirely, bringing the total to ~$20–30/mo.

## 5. Migration sequence (parallel, AWS stays live)

1. **Scaffold `infra/gcp/`** — DONE. Terraform tree with its own remote state
   in a GCS bucket (`de-duke-services-tfstate`, bootstrap step below).
2. **Apply GCP infra** — Cloud Run, Cloud SQL, GCS+CDN+LB, Pub/Sub, Secret
   Manager, Artifact Registry, Cloud DNS zone.
3. **Wire the backend to GCP** — image push to Artifact Registry; Secret
   Manager values point at GCP endpoints; **app-side items**: worker's
   Pub/Sub push-receive endpoint, SQS/SNS/SES client swaps, REDIS_URL
   handling once Memorystore is added.
4. **Migrate data** — export/import the production Postgres database into
   Cloud SQL; copy media from S3 to GCS.
5. **Cut over DNS** — set the Cloud DNS nameservers at the registrar; the
   api/cdn DNS records and managed certs complete once resolution points at
   the LB IP.
6. **Verify** — full smoke test against the live domain.
7. **Destroy AWS** — `terraform destroy` in `infra/environments/production`
   after a soak period.

Vercel-hosted apps (Admin Console, Marketing Site) and external APIs (Paystack,
Google Maps, Firebase) are unaffected.

## 6. Layout

```
infra/gcp/
├── README.md             # this proposal/build reference
├── versions.tf           # google provider + gcs backend
├── variables.tf          # all knobs, cost-minimizing defaults
├── locals.tf             # labels, image ref, connection name, FQDNs
├── main.tf               # enabled APIs, service account, IAM
├── secrets.tf            # Secret Manager (app secrets + DB credentials)
├── artifact_registry.tf  # backend image repo
├── cloud_sql.tf          # Cloud SQL Postgres 16 + database + user
├── storage_cdn.tf        # GCS bucket + Cloud CDN + HTTPS LB + cert
├── cloud_run.tf          # API + worker services, proxy sidecar, LB backend
├── pubsub.tf             # task topic + DLQ + push subscription + scheduler
├── dns.tf                # Cloud DNS zone + records (api/cdn/admin/marketing)
├── outputs.tf
├── terraform.tfvars.example
└── backend.hcl.example
```

## 7. Bootstrap (one-time, before first apply)

```bash
# 1. Create the Terraform state bucket in the target project
gcloud storage buckets create gs://de-duke-services-tfstate \
  --project=de-duke-services --location=europe-west1

# 2. Copy the example files and fill in values
cp infra/gcp/terraform.tfvars.example infra/gcp/terraform.tfvars
cp infra/gcp/backend.hcl.example infra/gcp/backend.hcl

# 3. Init with the remote backend, then plan (never apply without review)
cd infra/gcp
terraform init -backend-config=backend.hcl
terraform plan
```

## 8. Secrets

All secrets are seeded by Terraform with `REPLACE_ME` placeholders and
**populated by an operator after apply** -- the real values never live in this
repo. List of secrets in `de-duke-services`:

| Secret | Holds | Populated by |
|---|---|---|
| `de-duke-app-secrets` | JSON blob: Paystack, Google Maps, Firebase SA, **ZeptoMail API key**, Sentry, analytics, JWT, Gemini | operator (console or gcloud) |
| `de-duke-db-credentials` | `{"username","password"}` for Cloud SQL (auto-generated) | Terraform (random_password) |
| `de-duke-redis-url` | **Upstash Redis** connection string (`rediss://default:<token>@<region>.upstash.io:6379`) | operator (see below) |

**Populate the Redis secret (Upstash):**

```bash
echo -n 'rediss://default:<UPSTASH_TOKEN>@<region>.upstash.io:6379' | \
  gcloud secrets versions add de-duke-redis-url \
    --project=de-duke-services --data-file=-
```

> The Redis secret backs refresh tokens, rate-limit counters, and the
> semantic-search cache (app/core/cache.py via `REDIS_URL`). Upstash was
> chosen over GCP Memorystore because it is serverless/pay-per-use (~$0 at
> pre-launch traffic) versus Memorystore's always-on ~$35/mo minimum.

**Shape requirement for `FIREBASE_SERVICE_ACCOUNT_JSON`:** the app reads this
as a `str` and `json.loads()`es it (app/core/firebase.py), so inside the
`de-duke-app-secrets` JSON blob it must be stored **stringified**, not as a
nested object:

```json
{ "FIREBASE_SERVICE_ACCOUNT_JSON": "{ \"type\": \"service_account\", ... }" }
```

A nested dict causes `TypeError: the JSON object must be str` and a 500 on
`/v1/chat/token`. If you ever re-populate this value, stringify the service
account JSON first. (When updating the blob, the other top-level values stay
as-is; only this one must be a string.)

## 9. Prerequisites / inputs needed before apply

- [x] GCP target project confirmed: **`de-duke-services`** (billing enabled)
- [x] State backend: GCS bucket `de-duke-services-tfstate`
- [x] Redis: Upstash endpoint wired via `de-duke-redis-url` secret (populated by operator)
- [ ] Cloud Run image: confirm the backend Docker image builds for Cloud Run
      (Cloud Run requires a listening port via the configured container port;
      the FastAPI app listens on 8000 — already mirrored in the service)
- [ ] App-side wiring at cutover: worker Pub/Sub push endpoint, SQS/SNS/SES
      client swaps
- [ ] SES handling at cutover (keep vs. replace with Resend/Postmark)
- [ ] Who holds the `de-duke.com` registration (registrar), for the NS repoint
- [ ] Review the full `terraform plan` before any apply
