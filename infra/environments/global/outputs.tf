output "zone_id" {
  description = "Consumed by every environment's `data \"aws_route53_zone\" \"primary\"` lookup indirectly -- environments re-look-up by name rather than reading this output directly, so each environment's plan never depends on this state. Exposed here mainly for operator convenience (e.g. sanity-checking via `terraform output`)."
  value       = data.aws_route53_zone.primary.zone_id
}

output "alb_certificate_arn" {
  description = "Copy this into every environment's terraform.tfvars as `acm_certificate_arn` (eu-west-1 wildcard cert, DNS-validated -- required before any environment's ALB HTTPS listener is created, see modules/fargate_service/main.tf's has_certificate gate)."
  value       = aws_acm_certificate_validation.alb_wildcard.certificate_arn
}

output "cdn_certificate_arn" {
  description = "Copy this into every environment's terraform.tfvars as `cdn_acm_certificate_arn` (existing us-east-1 wildcard cert -- required before any environment's CloudFront distribution gets a custom domain/alias, see modules/s3_cdn's acm_certificate_arn_us_east_1 variable)."
  value       = data.aws_acm_certificate.cdn_wildcard.arn
}
