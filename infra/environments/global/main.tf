# De-Duke -- Global (account-level) DNS/cert plumbing
#
# This is NOT one of the deploy environments (development/staging/production)
# -- it holds the one hosted zone and the one ALB-facing certificate that
# every environment's Route53 records and ALB listener depend on, but that
# no single environment should own (deleting/recreating the "staging"
# environment must never be able to take down production's DNS or cert).
#
# Ownership split, deliberately:
#   - Hosted zone (de-duke.com)          -> already exists in AWS, created
#                                            outside Terraform. Read here as
#                                            a data source ONLY -- this repo
#                                            never creates/destroys the zone.
#   - Wildcard cert, us-east-1           -> already exists in AWS (created
#                                            outside Terraform), used for the
#                                            CloudFront/CDN distributions.
#                                            Also read as a data source only
#                                            (see outputs.tf).
#   - Wildcard cert, eu-west-1           -> did NOT already exist: the
#                                            existing cert is us-east-1 only,
#                                            and ACM certs attached to an ALB
#                                            listener must be in the SAME
#                                            region as the ALB (eu-west-1 for
#                                            every environment here). This
#                                            one IS created and DNS-validated
#                                            by Terraform below, against the
#                                            existing hosted zone.
#
# After `terraform apply` here, copy this config's `alb_certificate_arn`
# output into each environment's terraform.tfvars as `acm_certificate_arn`
# -- same manual-copy pattern this repo already uses for
# aws_account_suffix/gcp_project_id, and avoids coupling every
# environment's state to this one via terraform_remote_state.

data "aws_route53_zone" "primary" {
  name         = var.domain_name
  private_zone = false
}

# The existing us-east-1 wildcard cert, used by modules/s3_cdn's CloudFront
# distributions. Looked up by domain name rather than hardcoding an ARN so
# this keeps working if the cert is ever renewed/reissued (ACM auto-renews
# in place, but a manually reissued cert would get a new ARN).
#
# `domain` here must be the certificate's PRIMARY domain_name, not any of
# its Subject Alternative Names -- the aws_acm_certificate data source only
# matches against domain_name, never against the SAN list. This account's
# existing cert was issued with de-duke.com as the primary name and
# *.de-duke.com as a SAN (confirmed via `aws acm list-certificates
# --region us-east-1`), so filtering on "*.${var.domain_name}" returned
# "empty result" even though the cert -- and its wildcard SAN -- both
# exist. var.domain_name (the apex) is the correct filter.
data "aws_acm_certificate" "cdn_wildcard" {
  domain      = var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true

  # ACM certificates are regional resources -- this data source only sees
  # certs in the provider's configured region (eu-west-1, per versions.tf).
  # CloudFront's cert must be in us-east-1, so this lookup runs through an
  # explicit us-east-1 provider alias instead of the default provider.
  provider = aws.us_east_1
}

resource "aws_acm_certificate" "alb_wildcard" {
  domain_name       = "*.${var.domain_name}"
  validation_method = "DNS"

  # Also cover the bare apex (de-duke.com with no subdomain) in case a
  # future environment ever needs it -- a wildcard alone does NOT match the
  # zero-label apex.
  subject_alternative_names = [var.domain_name]

  lifecycle {
    create_before_destroy = true
  }
}

# ACM DNS validation records, created in the existing hosted zone. This is
# the only way this config ever writes to the zone at global scope -- it
# never touches the zone's other existing records.
resource "aws_route53_record" "alb_wildcard_validation" {
  for_each = {
    for dvo in aws_acm_certificate.alb_wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_route53_zone.primary.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "alb_wildcard" {
  certificate_arn         = aws_acm_certificate.alb_wildcard.arn
  validation_record_fqdns = [for r in aws_route53_record.alb_wildcard_validation : r.fqdn]
}
