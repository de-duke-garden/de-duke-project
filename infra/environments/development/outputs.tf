output "alb_dns_name" {
  description = "Consumed by .github/workflows/backend-deploy.yml's smoke-test job."
  value       = module.backend.alb_dns_name
}

output "cluster_name" {
  value = module.backend.cluster_name
}
