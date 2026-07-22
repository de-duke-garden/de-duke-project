locals {
  common_tags = {
    Project     = "de-duke"
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # Public subdomains for this environment (root domain owned by the
  # existing, externally-managed Route53 zone -- see the `data
  # "aws_route53_zone" "primary"` lookup in main.tf). Development uses the
  # "dev-" prefix to keep it unambiguous from staging's "staging-" prefix
  # and production's bare "api"/"cdn".
  domain_name = "de-duke.com"
  api_fqdn    = "dev-api.${local.domain_name}"
  cdn_fqdn    = "cdn-dev.${local.domain_name}"
}
