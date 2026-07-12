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
  default = "staging"
}

variable "availability_zones" {
  description = "Map of AZ name -> subnet CIDRs. At least 2 required (Multi-AZ baseline)."
  type = map(object({
    public_cidr  = string
    private_cidr = string
  }))
  default = {
    "eu-west-1a" = { public_cidr = "10.1.0.0/24", private_cidr = "10.1.10.0/24" }
    "eu-west-1b" = { public_cidr = "10.1.1.0/24", private_cidr = "10.1.11.0/24" }
  }
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener. Leave blank until a domain/cert exists for this environment."
  type        = string
  default     = ""
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
