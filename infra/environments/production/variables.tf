variable "aws_region" {
  description = "AWS region closest to the primary Nigerian user base (architecture.md Regions)."
  type        = string
  default     = "eu-west-1"
}

variable "gcp_project_id" {
  description = "GCP project ID hosting the Firestore chat store for this environment."
  type        = string
}

variable "gcp_region" {
  type    = string
  default = "europe-west1"
}

variable "environment" {
  type    = string
  default = "production"
}

variable "availability_zones" {
  description = "Map of AZ name -> subnet CIDRs. At least 2 required (Multi-AZ baseline)."
  type = map(object({
    public_cidr  = string
    private_cidr = string
  }))
  default = {
    "eu-west-1a" = { public_cidr = "10.2.0.0/24", private_cidr = "10.2.10.0/24" }
    "eu-west-1b" = { public_cidr = "10.2.1.0/24", private_cidr = "10.2.11.0/24" }
  }
}

variable "aws_account_suffix" {
  description = "Short unique suffix for globally-unique resource names (e.g. S3 bucket). Provide your AWS account ID or a short hash."
  type        = string
}

variable "image_tag" {
  description = "Tag of the real Backend API Service image to deploy, forwarded to modules/fargate_service. Left as the default empty string before CI has ever pushed one (e.g. a fresh environment's very first apply) -- see modules/fargate_service/main.tf's placeholder-image fallback for why that case is handled explicitly rather than defaulting to a nonexistent `:latest` tag."
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "eu-west-1 ACM cert ARN for the ALB HTTPS listener -- copy from `terraform output alb_certificate_arn` in environments/global (see infra/README.md's \"DNS & certificates\" section). Leave blank until that's been applied (ALB serves HTTP-only until then, see modules/fargate_service's has_certificate gate)."
  type        = string
  default     = ""
}

variable "cdn_acm_certificate_arn" {
  description = "us-east-1 ACM cert ARN for the media CDN's CloudFront distribution -- copy from `terraform output cdn_certificate_arn` in environments/global. Leave blank until that's been applied (CloudFront falls back to its default *.cloudfront.net cert/domain, see modules/s3_cdn's has_custom_domain gate)."
  type        = string
  default     = ""
}

# CNAME target Vercel gives for admin.de-duke.com -- unique per Vercel
# project, no shared default. Set via TF_VERCEL_CNAME_TARGET.
variable "vercel_cname_target" {
  description = "CNAME target Vercel gives for admin.de-duke.com."
  type        = string
  default     = ""
}

variable "vercel_apex_ips" {
  description = "IP address(es) Vercel gives for the Marketing Site's bare de-duke.com apex (A record, not CNAME)."
  type        = list(string)
  default     = ["76.76.21.21"]
}
