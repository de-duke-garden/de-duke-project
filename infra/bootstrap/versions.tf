# One-time bootstrap: creates the S3 bucket that every environment's own
# Terraform state lives in. This config's own state stays local (there is
# nothing to bootstrap for the bootstrapper itself) -- it is run exactly
# once per AWS account, by a human operator, before any environment's
# `terraform init -backend-config=backend.hcl` can succeed.
terraform {
  required_version = ">= 1.11.0" # required for S3 native state locking (use_lockfile)
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}
