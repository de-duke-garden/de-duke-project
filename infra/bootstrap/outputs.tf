output "state_bucket_name" {
  description = "Pass this as `bucket` in every environment's backend.hcl."
  value       = aws_s3_bucket.terraform_state.id
}
