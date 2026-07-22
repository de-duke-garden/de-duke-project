# De-Duke — File Storage Service + CDN module
# S3 for listing photos and verification document uploads, fronted by
# CloudFront so photo-heavy screens (Search Results, Listing Detail) load
# fast on lower-bandwidth mobile connections (architecture.md).

resource "aws_s3_bucket" "media" {
  bucket = "${var.environment}-de-duke-media-${var.account_suffix}"
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id
  versioning_configuration {
    status = "Enabled" # guards against accidental overwrite/deletion (architecture.md Backup & Recovery)
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "media" {
  bucket                  = aws_s3_bucket.media.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "media" {
  name                              = "${var.environment}-de-duke-media-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Mirrors modules/fargate_service/main.tf's has_certificate gate: a custom
# domain requires a real cert (CloudFront rejects `aliases` without a
# matching non-default viewer_certificate), so both are only wired up once
# an ACM cert ARN has actually been supplied.
locals {
  has_custom_domain = var.cdn_domain_name != "" && var.acm_certificate_arn_us_east_1 != ""
}

resource "aws_cloudfront_distribution" "media" {
  enabled             = true
  default_root_object = ""
  comment             = "De-Duke media CDN (${var.environment})"
  aliases             = local.has_custom_domain ? [var.cdn_domain_name] : []

  origin {
    domain_name              = aws_s3_bucket.media.bucket_regional_domain_name
    origin_id                = "s3-media"
    origin_access_control_id = aws_cloudfront_origin_access_control.media.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-media"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 604800
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = local.has_custom_domain ? null : true
    acm_certificate_arn            = local.has_custom_domain ? var.acm_certificate_arn_us_east_1 : null
    ssl_support_method             = local.has_custom_domain ? "sni-only" : null
    minimum_protocol_version       = local.has_custom_domain ? "TLSv1.2_2021" : null
  }

  tags = var.tags
}

data "aws_iam_policy_document" "media_cloudfront_read" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.media.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.media.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "media" {
  bucket = aws_s3_bucket.media.id
  policy = data.aws_iam_policy_document.media_cloudfront_read.json
}
