terraform {
  required_version = ">= 1.11.0" # required for S3 native state locking (use_lockfile)
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state in S3, locked via S3's own native conditional-write locking
  # (use_lockfile) -- no DynamoDB lock table (deprecated for this purpose as
  # of Terraform 1.11). Bucket/key/region are supplied via
  # `terraform init -backend-config=backend.hcl` (see backend.hcl.example
  # and infra/bootstrap/ for the one-time bucket creation) rather than
  # hardcoded here, so the same config works across environments.
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.common_tags
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}
