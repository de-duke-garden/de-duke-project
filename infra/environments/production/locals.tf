locals {
  common_tags = {
    Project     = "de-duke"
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # Public subdomains for this environment -- production is the only one
  # without an environment prefix ("api"/"cdn" rather than "prod-api" etc.),
  # matching the recommended scheme confirmed with the operator. See
  # development/locals.tf's identical comment for why the zone itself isn't
  # created here.
  domain_name = "de-duke.com"
  api_fqdn    = "api.${local.domain_name}"
  cdn_fqdn    = "cdn.${local.domain_name}"
}
