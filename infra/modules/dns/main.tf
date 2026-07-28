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
  # Both terms are resolvable at plan time. Deliberately NOT also testing
  # `var.cdn_domain_name != ""`: that's modules/s3_cdn's CloudFront
  # `domain_name`, a computed attribute which is unknown until apply on a
  # fresh environment -- and `count` must be known at plan time, so
  # including it failed production's very first plan with "Invalid count
  # argument". The test was redundant anyway (a distribution this config
  # always creates never has an empty domain_name); the real gate -- "has
  # the us-east-1 cert been issued, so CloudFront recognizes cdn_fqdn as
  # one of its own aliases" -- is carried entirely by create_cdn_record.
  # Referencing the unknown value in `alias` below stays fine: unknown
  # attribute values are legal, only an unknown `count` is not.
  count   = var.create_cdn_record && var.cdn_fqdn != "" ? 1 : 0
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

  # Unlike every other record here, the apex already existed before
  # Terraform did -- it was created by hand when the Vercel-hosted
  # marketing site went live, inside the externally-managed zone (see
  # this file's header). Route53's ChangeResourceRecordSets uses CREATE,
  # which fails with InvalidChangeBatch "but it already exists" on a
  # name/type pair that's already present -- exactly what broke
  # production's first apply. allow_overwrite switches that to UPSERT so
  # Terraform adopts the existing record instead of colliding with it.
  #
  # Safe specifically because the live value already equals the desired
  # one (de-duke.com A -> 76.76.21.21, matching vercel_apex_ips'
  # default), so adoption is a no-op in DNS terms -- nothing resolves
  # differently before and after. Kept scoped to this one record rather
  # than applied module-wide: everywhere else, a pre-existing record
  # SHOULD be a loud failure rather than something silently clobbered.
  allow_overwrite = true
}

# www.de-duke.com (production only) -> Vercel, via CNAME.
#
# Not optional despite the apex record above already existing: Vercel
# treats www as the Marketing Site project's PRIMARY domain, so it
# answers the apex with a 308 redirect to https://www.de-duke.com/
# rather than serving the site there. Without this record that redirect
# target is NXDOMAIN, and the site is unreachable on both hostnames even
# though the apex A record resolves and reaches Vercel correctly.
#
# Uses Vercel's newer per-project *.vercel-dns-017.com target rather than
# the legacy shared cname.vercel-dns.com, per the value shown in the
# project's Domains tab (the legacy record still works, but Vercel is
# expanding its IP range and recommends the per-project one).
resource "aws_route53_record" "marketing_www" {
  count   = var.create_marketing_record && var.marketing_www_fqdn != "" && var.vercel_marketing_cname_target != "" ? 1 : 0
  zone_id = var.zone_id
  name    = var.marketing_www_fqdn
  type    = "CNAME"
  ttl     = 300
  records = [var.vercel_marketing_cname_target]
}
