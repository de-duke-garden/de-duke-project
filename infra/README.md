# De-Duke Infrastructure (Terraform)

Provisions everything defined in `docs/De-Duke/architecture.md`: networking
(Multi-AZ VPC), the Backend API Service on Fargate behind an ALB + WAF, the
Primary Database (RDS PostgreSQL + PostGIS/pgvector) with read replicas, the
Redis Caching Layer, the SQS Task Queue, S3 + CloudFront for media, ECR, and
the AWS Secrets Manager secret for application-level third-party credentials.

## Status

**Modules are written. Nothing has been applied.** Do not run `terraform
apply` in any environment until explicitly instructed.

## Layout

```
infra/
├── bootstrap/          # One-time, per-AWS-account: creates the S3 state bucket
│                        # (own local state -- nothing else can use a remote
│                        # backend before this bucket exists)
├── modules/            # Reusable building blocks, one per AWS/GCP concern
│   ├── networking/      # VPC, subnets, NAT, route tables (Multi-AZ)
│   ├── rds_postgres/    # Primary Database, writer + read replicas
│   ├── redis/           # Caching Layer (Multi-AZ in staging/production)
│   ├── sqs/              # Task Queue + dead-letter queue
│   ├── s3_cdn/           # File Storage + CloudFront CDN
│   ├── secrets/          # App-level secret container (REPLACE_ME placeholders)
│   ├── ecr/              # Container registry for the Backend API Service image
│   ├── fargate_service/  # ALB, ECS cluster/service/task, RDS Proxy, autoscaling
│   └── waf/              # Web Application Firewall in front of the ALB
└── environments/
    ├── development/      # Smallest footprint: single-AZ RDS, no read replicas, 1 Redis node
    ├── staging/          # Not yet configured — mirror development, then scale up per architecture.md
    └── production/       # Not yet configured — Multi-AZ everywhere, read replicas from launch
```

Each environment stores its state remotely in a single shared S3 bucket
(created once by `infra/bootstrap/`), namespaced by object key
(`development/terraform.tfstate`, etc.) -- never local state, so more than
one operator can safely run Terraform against the same environment.
Locking uses S3's own native conditional-write locking (`use_lockfile` in
each environment's `backend "s3" {}` block, supplied via
`-backend-config=backend.hcl`) -- **not DynamoDB**: DynamoDB-based
Terraform state locking was deprecated once S3 native locking reached
general availability in Terraform 1.11 (Feb 2025), so a new project has no
reason to stand up a lock table on its way out. Requires Terraform
`>= 1.11.0`.

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

0. **One time per AWS account:** in `infra/bootstrap/`, copy
   `terraform.tfvars.example` to `terraform.tfvars`, fill it in, then
   `terraform init && terraform apply` there first -- this creates the S3
   state bucket every environment's backend depends on. Note its
   `state_bucket_name` output.
1. Copy `environments/<env>/terraform.tfvars.example` to
   `terraform.tfvars` (gitignored) and fill in the `REPLACE_ME` values
   (GCP project ID, AWS account suffix, ACM certificate ARN once available).
2. Copy `environments/<env>/backend.hcl.example` to `backend.hcl`
   (gitignored) and fill in `bucket` (from step 0's output) and `region`.
3. Ensure your AWS CLI credentials and `gcloud auth` are active for the
   target account/project.
4. Run `terraform init -backend-config=backend.hcl` inside
   `environments/<env>/`.
5. Run `terraform plan` and review the plan carefully before ever running
   `terraform apply` — and only run `apply` when explicitly told to.
