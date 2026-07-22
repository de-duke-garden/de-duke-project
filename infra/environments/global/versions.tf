terraform {
  required_version = ">= 1.11.0" # required for S3 native state locking (use_lockfile)
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Remote state in S3, same pattern as every other environment (see
  # environments/staging/backend.hcl.example) -- own state key
  # ("global/terraform.tfstate") since this isn't a deploy environment,
  # it's shared account-level DNS/cert plumbing that every environment
  # reads from (its ALB cert ARN) but none of them own.
  backend "s3" {}
}

# Region matters here: this is the ALB-facing certificate, and ACM
# certificates used by an Application Load Balancer listener must live in
# the SAME region as that ALB (eu-west-1 for every de-duke environment --
# see environments/*/variables.tf's aws_region default). This is distinct
# from the CDN-facing cert (modules/s3_cdn's acm_certificate_arn_us_east_1),
# which CloudFront requires to be in us-east-1 regardless of where the
# distribution's origin lives.
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project   = "de-duke"
      ManagedBy = "terraform"
      Scope     = "global"
    }
  }
}

# CloudFront/ACM require the viewer certificate to exist in us-east-1
# regardless of which region the distribution's origin or the rest of this
# account's resources live in. Used only to look up the already-existing
# wildcard cert (data "aws_acm_certificate" "cdn_wildcard" in main.tf) --
# nothing is created through this alias.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = {
      Project   = "de-duke"
      ManagedBy = "terraform"
      Scope     = "global"
    }
  }
}
