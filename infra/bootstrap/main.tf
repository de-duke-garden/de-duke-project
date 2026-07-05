# Single S3 bucket holding every environment's Terraform state, namespaced
# by object key (development/terraform.tfstate, staging/terraform.tfstate,
# production/terraform.tfstate) rather than one bucket per environment --
# simpler to provision once and lock down.
#
# State locking uses S3's native conditional-write locking (`use_lockfile`
# on each environment's own `backend "s3"` block) -- no DynamoDB lock table.
# DynamoDB-based Terraform locking was deprecated once S3 native locking
# reached general availability in Terraform 1.11 (Feb 2025); a new project
# has no reason to stand up a lock table that's already on its way out.
resource "aws_s3_bucket" "terraform_state" {
  bucket = "de-duke-terraform-state-${var.aws_account_suffix}"

  # Terraform state is effectively the platform's source of truth for what
  # infra exists -- losing it is a real incident, not an inconvenience.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
