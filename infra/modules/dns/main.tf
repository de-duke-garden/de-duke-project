# De-Duke -- Public DNS module
# Creates the per-environment subdomain records inside the existing,
# externally-managed de-duke.com Route53 hosted zone. The zone itself and
# the CloudFront-facing wildcard ACM cert are NOT created here -- they
# already exist in AWS (created outside Terraform) and are read as data
# sources at each environment's root (see environments/*/main.tf's
# `data "aws_route53_zone" "primary"` block). This module only ever
# creates/updates/deletes the records listed below, never the zone.

# api.de-duke.com (prod) / staging-api.de-duke.com / dev-api.de-duke.com
# -> this environment's ALB. Alias (not CNAME) so it can be used at the
# zone apex too and so Route53 resolves it without an extra DNS hop.
resource "aws_route53_record" "api" {
  zone_id = var.zone_id
  name    = var.api_fqdn
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# cdn.de-duke.com (prod) / cdn-staging.de-duke.com / cdn-dev.de-duke.com
# -> this environment's CloudFront distribution. Only created once the
# distribution has been given a matching alias + us-east-1 cert (see
# modules/s3_cdn) -- otherwise CloudFront rejects requests for a hostname
# it doesn't recognize as one of its own aliases, so this record must not
# exist ahead of that.
resource "aws_route53_record" "cdn" {
  count   = var.create_cdn_record && var.cdn_fqdn != "" && var.cdn_domain_name != "" ? 1 : 0
  zone_id = var.zone_id
  name    = var.cdn_fqdn
  type    = "A"

  alias {
    name                   = var.cdn_domain_name
    zone_id                = local.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}
