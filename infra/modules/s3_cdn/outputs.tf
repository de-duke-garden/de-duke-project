output "bucket_name" {
  value = aws_s3_bucket.media.bucket
}

output "cdn_domain_name" {
  value = aws_cloudfront_distribution.media.domain_name
}
