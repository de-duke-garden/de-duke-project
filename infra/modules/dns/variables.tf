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

variable "create_admin_record" {
  description = "Whether to create the Admin Web Console CNAME record."
  type        = bool
  default     = false
}

variable "admin_fqdn" {
  description = "Fully-qualified subdomain for this environment's Admin Web Console, e.g. \"admin.de-duke.com\", \"staging-admin.de-duke.com\", or \"dev-admin.de-duke.com\"."
  type        = string
  default     = ""
}

variable "vercel_cname_target" {
  description = "CNAME target Vercel gives for this environment's admin subdomain. Unique per Vercel project, no shared default -- get it from the Vercel dashboard or `vercel domains inspect <fqdn>`. Left empty until set."
  type        = string
  default     = ""
}

variable "create_marketing_record" {
  description = "Whether to create the Marketing Site apex A record. Production-only."
  type        = bool
  default     = false
}

variable "marketing_fqdn" {
  description = "The bare root domain the Marketing Site is served from, e.g. \"de-duke.com\"."
  type        = string
  default     = ""
}

variable "vercel_apex_ips" {
  description = "IP address(es) Vercel gives for a bare apex/root domain (A record, not CNAME -- see main.tf's `marketing` record). Shared/stable across every Vercel project, unlike vercel_cname_target above."
  type        = list(string)
  default     = ["76.76.21.21"]
}

# CloudFront's hosted zone ID is the same fixed value for every CloudFront
# distribution in every AWS account/region -- not looked up, it's a
# documented AWS constant (see AWS docs: "Amazon Route 53 Alias Target").
locals {
  cloudfront_hosted_zone_id = "Z2FDTNDATAQYW2"
}
