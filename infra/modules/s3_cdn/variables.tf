variable "environment" { type = string }
variable "account_suffix" {
  description = "Unique suffix (e.g. AWS account ID or short hash) to keep the bucket name globally unique."
  type        = string
}
variable "tags" {
  type    = map(string)
  default = {}
}

# Custom domain for the CDN (e.g. "cdn.de-duke.com" / "cdn-staging.de-duke.com").
# Left blank by default -- a fresh environment with no cert yet keeps using
# CloudFront's own default *.cloudfront.net domain (see main.tf's
# has_custom_domain gate), same "leave blank until it exists" pattern as
# modules/fargate_service's acm_certificate_arn.
variable "cdn_domain_name" {
  type    = string
  default = ""
}

# CloudFront requires the viewer certificate to be in us-east-1 REGARDLESS
# of the distribution's origin region -- this is intentionally a separate
# cert/ARN from modules/fargate_service's acm_certificate_arn (which must be
# in the ALB's own region, eu-west-1 here). See
# environments/global/main.tf's cdn_wildcard data source for where this
# comes from (the existing externally-managed us-east-1 wildcard cert).
variable "acm_certificate_arn_us_east_1" {
  type    = string
  default = ""
}
