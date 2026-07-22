# De-Duke -- Public DNS module
# Creates the per-environment subdomain records inside the existing,
# externally-managed de-duke.com Route53 hosted zone. The zone itself and
# the CloudFront-facing wildcard ACM cert are NOT created here -- they
# already exist in AWS (created outside Terraform) and are read as data
# sources at each environment's root (see environments/*/main.tf's
# `data "aws_route53_zone" "primary"` block). This module only ever
# creates/updates/deletes the records listed below, never the zone.
#
# Admin Web Console + Marketing Site are Vercel-hosted, not ECS/Fargate --
# their DNS still lives here. Vercel manages its own TLS certs, so unlike
# api/cdn above, no ACM cert plumbing is needed for either record below.

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

# admin.de-duke.com (prod) / staging-admin.de-duke.com / dev-admin.de-duke.com
# -> Vercel, via CNAME. vercel_cname_target is unique per Vercel project
# (no shared default), so the record is only created once it's set.
resource "aws_route53_record" "admin" {
  count   = var.create_admin_record && var.admin_fqdn != "" && var.vercel_cname_target != "" ? 1 : 0
  zone_id = var.zone_id
  name    = var.admin_fqdn
  type    = "CNAME"
  ttl     = 300
  records = [var.vercel_cname_target]
}

# de-duke.com (production only) -> Vercel, via A record. A CNAME is not
# valid at a zone apex, so this uses Vercel's apex IP instead.
resource "aws_route53_record" "marketing" {
  count   = var.create_marketing_record && var.marketing_fqdn != "" ? 1 : 0
  zone_id = var.zone_id
  name    = var.marketing_fqdn
  type    = "A"
  ttl     = 300
  records = var.vercel_apex_ips
}
