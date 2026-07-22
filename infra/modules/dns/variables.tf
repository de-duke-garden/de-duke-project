variable "zone_id" {
  description = "Hosted zone ID of the existing de-duke.com Route53 zone (looked up as a data source at the environment root -- this module never creates or destroys the zone itself)."
  type        = string
}

variable "api_fqdn" {
  description = "Fully-qualified subdomain for this environment's public backend API, e.g. \"api.de-duke.com\" (production) or \"staging-api.de-duke.com\"."
  type        = string
}

variable "alb_dns_name" {
  description = "DNS name of this environment's ALB (module.backend.alb_dns_name)."
  type        = string
}

variable "alb_zone_id" {
  description = "Hosted zone ID of this environment's ALB, required for an alias (not CNAME) record (module.backend.alb_zone_id)."
  type        = string
}

variable "create_cdn_record" {
  description = "Whether to create the media CDN alias record. False until the CloudFront distribution has a us-east-1 ACM cert + alias configured (see modules/s3_cdn's cdn_domain_name/acm_certificate_arn_us_east_1 variables)."
  type        = bool
  default     = true
}

variable "cdn_fqdn" {
  description = "Fully-qualified subdomain for this environment's media CDN, e.g. \"cdn.de-duke.com\" (production) or \"cdn-staging.de-duke.com\"."
  type        = string
  default     = ""
}

variable "cdn_domain_name" {
  description = "CloudFront distribution domain name to alias to (module.media.cdn_domain_name)."
  type        = string
  default     = ""
}

# CloudFront's hosted zone ID is the same fixed value for every CloudFront
# distribution in every AWS account/region -- not looked up, it's a
# documented AWS constant (see AWS docs: "Amazon Route 53 Alias Target").
locals {
  cloudfront_hosted_zone_id = "Z2FDTNDATAQYW2"
}
