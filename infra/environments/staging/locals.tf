locals {
  common_tags = {
    Project     = "de-duke"
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # Public subdomains for this environment -- see development/locals.tf's
  # identical comment for why the zone itself isn't created here.
  domain_name = "de-duke.com"
  api_fqdn    = "staging-api.${local.domain_name}"
  cdn_fqdn    = "cdn-staging.${local.domain_name}"

  admin_fqdn = "staging-admin.${local.domain_name}"
}
