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

Each environment has its own local Terraform state file (`terraform.tfstate`,
gitignored) — no shared remote state yet. If more than one person needs to
run Terraform against the same environment, migrate to an S3 backend with a
DynamoDB lock table before that happens (not yet done).

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
   (GCP project ID, AWS account suffix, ACM certificate ARN once available).
2. Ensure your AWS CLI credentials and `gcloud auth` are active for the
   target account/project.
3. Run `terraform init` inside `environments/<env>/`.
4. Run `terraform plan` and review the plan carefully before ever running
   `terraform apply` — and only run `apply` when explicitly told to.
