# De-Duke Infrastructure (Terraform)

Provisions everything defined in `docs/De-Duke/architecture.md`: networking
(Multi-AZ VPC), the Backend API Service on Fargate behind an ALB + WAF, the
Primary Database (RDS PostgreSQL + PostGIS/pgvector) with read replicas, the
Redis Caching Layer, the SQS Task Queue, S3 + CloudFront for media, ECR, and
the AWS Secrets Manager secret for application-level third-party credentials.

## Apply policy

CI is the default way to apply -- see "CI/CD: which workflow applies infra
changes" below. Running `terraform apply` locally is a supported fallback,
never the first choice: state is remote in S3 with native locking, so a
local apply can't corrupt or race against a CI-driven one, but it skips
the PR review + plan-preview path CI gives every change.

## Layout

```
infra/
├── modules/            # Reusable building blocks, one per AWS/GCP concern
│   ├── networking/      # VPC, subnets, NAT, route tables (Multi-AZ)
│   ├── rds_postgres/    # Primary Database, writer + read replicas
│   ├── redis/           # Caching Layer (Multi-AZ in staging/production)
│   ├── sqs/              # Task Queue + dead-letter queue
│   ├── s3_cdn/           # File Storage + CloudFront CDN
│   ├── secrets/          # App-level secret container (REPLACE_ME placeholders)
│   ├── ecr/              # Container registry for the Backend API Service image
│   ├── fargate_service/  # ALB, ECS cluster/service/task, RDS Proxy, autoscaling
│   ├── waf/              # Web Application Firewall in front of the ALB
│   └── dns/              # Per-environment Route53 alias records (api./cdn. subdomains)
└── environments/
    ├── global/            # NOT a deploy environment -- one-time DNS/cert bootstrap
    │                      # shared by every environment below (see its own main.tf header)
    ├── development/       # Smallest footprint: single-AZ RDS, no read replicas, 1 Redis node
    ├── staging/           # Not yet configured — mirror development, then scale up per architecture.md
    └── production/        # Not yet configured — Multi-AZ everywhere, read replicas from launch
```

## DNS & certificates (de-duke.com)

`de-duke.com`'s Route53 hosted zone and its `*.de-duke.com` ACM certificate
(us-east-1, used for CloudFront) already exist in AWS -- both created
outside Terraform. This project only ever **reads** them as data sources
(`data "aws_route53_zone"` / `data "aws_acm_certificate"`); nothing here
can delete or recreate either one.

What Terraform *does* create:

- **`environments/global`** — a one-time bootstrap, applied once (not part
  of the development → staging → production matrix). It issues and
  DNS-validates a second wildcard cert in **eu-west-1**, because ACM
  certificates attached to an ALB listener must live in the same region as
  the ALB, and the existing wildcard cert is us-east-1-only (CloudFront's
  requirement, not the ALB's). After applying it, copy its two outputs —
  `alb_certificate_arn` and `cdn_certificate_arn` — into every
  environment's `terraform.tfvars` (`acm_certificate_arn` and
  `cdn_acm_certificate_arn` respectively).
- **Each environment's `module "dns"`** (`modules/dns`) — creates that
  environment's public subdomain alias records once the corresponding cert
  var is populated:
  | Environment | API subdomain | CDN subdomain |
  |---|---|---|
  | production | `api.de-duke.com` | `cdn.de-duke.com` |
  | staging | `staging-api.de-duke.com` | `cdn-staging.de-duke.com` |
  | development | `dev-api.de-duke.com` | `cdn-dev.de-duke.com` |

  The API record is always created (points at the ALB, which always
  exists). The CDN record is only created once `cdn_acm_certificate_arn`
  is set — CloudFront rejects traffic for a hostname that isn't yet
  configured as one of its own `aliases`, so the DNS record must not exist
  ahead of that.

Each environment stores its state remotely in a pre-existing, externally
managed S3 bucket (not provisioned by this Terraform config -- the bucket
already exists), namespaced by object key (`development/terraform.tfstate`,
etc.) -- never local state, so more than one operator can safely run
Terraform against the same environment. Locking uses S3's own native
conditional-write locking (`use_lockfile` in each environment's
`backend "s3" {}` block, supplied via `-backend-config=backend.hcl`) --
**not DynamoDB**: DynamoDB-based Terraform state locking was deprecated
once S3 native locking reached general availability in Terraform 1.11
(Feb 2025), so a new project has no reason to stand up a lock table on
its way out. Requires Terraform `>= 1.11.0`.

## Secrets model

- **Application secrets** (Paystack, Google Maps, FCM, SES, Firestore service
  account, Sentry, analytics, JWT signing key): a single Secrets Manager
  secret per environment (`modules/secrets`), seeded with `REPLACE_ME` for
  every field. After the first `apply`, an operator populates real values
  directly in the AWS Secrets Manager console. Terraform will never
  overwrite those values on a later `apply` (`ignore_changes` on the secret
  string).
- **Database credentials**: a second secret, created and rotated
  automatically by AWS itself via RDS's `manage_master_user_password`
  feature — nothing to populate manually.
- **Local development**: copy real values from Secrets Manager into your own
  `apps/backend/.env` (gitignored). `apps/backend/.env.example` documents
  every variable name.

## Before running `terraform init`/`plan`/`apply`

1. Copy `environments/<env>/terraform.tfvars.example` to
   `terraform.tfvars` (gitignored) and fill in the `REPLACE_ME` values
   (GCP project ID, AWS account suffix, and the two ACM certificate ARNs
   from `environments/global`'s outputs — see "DNS & certificates" above).
   `environments/global` itself has no `REPLACE_ME` values to fill in
   (its `variables.tf` defaults already match this project's real domain/
   region); only its `backend.hcl` needs to be copied and filled in per
   step 2 below.
2. Copy `environments/<env>/backend.hcl.example` to `backend.hcl`
   (gitignored) and fill in `bucket` (the name of the already-existing S3
   state bucket) and `region`.
3. Ensure your AWS CLI credentials and `gcloud auth` are active for the
   target account/project.
4. Run `terraform init -backend-config=backend.hcl` inside
   `environments/<env>/`.
5. Run `terraform plan` and review the plan carefully before ever running
   `terraform apply` — and only run `apply` when explicitly told to.

## CI/CD: which workflow applies infra changes

- Changes under `apps/backend/**` go through `.github/workflows/backend-deploy.yml`: build/push image → `terraform apply` (with the new image tag) → rolling deploy → smoke test → automatic rollback on failure. If a push touches both `apps/backend/**` and `infra/**`, this workflow's apply covers the combined change.
- Changes under `infra/**` alone go through `.github/workflows/infra-terraform.yml` instead — **not** `backend-deploy.yml`. On a pull request it runs `fmt`/`init`/`validate`/`plan` only (no apply), giving a plan preview before merge. On push to `main` it runs `terraform apply` directly, *unless* the same push also touched `apps/backend/**`, in which case it skips its own apply and lets `backend-deploy.yml` handle it, so the two workflows never both run `terraform apply` against the same environment's state at once. Both workflows additionally share the same Terraform concurrency group as defense-in-depth against that.
- **Any apply — from either workflow — must always pass an explicit `-var="image_tag=..."`.** `modules/fargate_service`'s `image_tag` variable defaults to `""`, which deploys the placeholder `nginx` image described below. An infra-only apply that let this default through would silently revert the live Fargate service to the placeholder. Both workflows guard against this by looking up the currently-deployed image tag from ECS before planning/applying and passing it back in explicitly, so an infra-only change only ever shows/applies the actual infra diff.
- **`AWS_REGION` and `TF_STATE_BUCKET_REGION` are two different GitHub variables on purpose — do not merge them.** `AWS_REGION` is where actual resources deploy (the AWS CLI/provider region, e.g. `eu-west-1`). `TF_STATE_BUCKET_REGION` is wherever the Terraform state S3 bucket itself happens to live (an S3 bucket's region is fixed at creation and has no relationship to which region your resources deploy into — this project's state bucket lives in `us-east-1` while resources deploy to `eu-west-1`). Using one variable for both breaks either `terraform init` (S3 returns a 301 "wrong region" redirect) or every AWS CLI call that omits an explicit `--region` (ECR/ECS lookups silently query the wrong region and report the resource as missing).

## First apply, before any image has ever been pushed to ECR

`terraform apply` provisions infrastructure only -- it never builds or
pushes a container image (that is `.github/workflows/backend-deploy.yml`'s
job, via the AWS CLI/Docker). On a fresh environment's very first apply,
`modules/fargate_service` has nothing real to deploy yet, so it points the
task definition at a small public placeholder image (`nginx`, remapped to
this service's port) instead of an ECR tag that doesn't exist. The ALB
health check will legitimately fail against that placeholder -- expected,
and harmless (the ECS service resource does not set
`wait_for_steady_state`, so this never blocks `apply` itself). The next
push to `apps/backend/` on `main` builds and pushes the real image and
`terraform apply`s again with a real `image_tag`, replacing the
placeholder for good.
