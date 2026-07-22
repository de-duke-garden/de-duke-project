output "api_fqdn" {
  value = aws_route53_record.api.name
}

output "cdn_fqdn" {
  value = length(aws_route53_record.cdn) > 0 ? aws_route53_record.cdn[0].name : null
}
