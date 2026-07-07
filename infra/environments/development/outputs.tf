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
