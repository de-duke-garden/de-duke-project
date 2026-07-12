output "alb_dns_name" {
  description = "Consumed by .github/workflows/backend-deploy.yml's smoke-test job."
  value       = module.backend.alb_dns_name
}

output "cluster_name" {
  value = module.backend.cluster_name
}

# Consumed by .github/workflows/backend-deploy.yml's migrate step, to run
# `alembic upgrade head` as a one-off ECS task using the exact same
# network placement as the real backend-api service (so it reaches the
# RDS Proxy the same way the app itself does).
output "private_subnet_ids" {
  value = module.networking.private_subnet_ids
}

output "service_security_group_id" {
  value = aws_security_group.backend_service.id
}

# Consumed by .github/workflows/load-test-full.yml's "Resolve database
# connection string" steps (seed + verify jobs) -- these two outputs are
# how CI derives the same DATABASE_URL the running backend task assembles
# itself at startup (DB_PROXY_ENDPOINT + Secrets Manager, see
# apps/backend/app/core/config.py's _apply_deployed_secrets), instead of
# requiring a separately-maintained, drift-prone plaintext DB URL secret.
output "db_proxy_endpoint" {
  value = module.backend.db_proxy_endpoint
}

output "db_secret_arn" {
  description = "RDS-managed master user secret ARN (username/password JSON) -- see modules/rds_postgres's manage_master_user_password."
  value       = module.rds.writer_secret_arn
}
