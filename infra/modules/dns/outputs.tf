output "api_fqdn" {
  value = aws_route53_record.api.name
}

output "cdn_fqdn" {
  value = length(aws_route53_record.cdn) > 0 ? aws_route53_record.cdn[0].name : null
}

output "admin_fqdn" {
  value = length(aws_route53_record.admin) > 0 ? aws_route53_record.admin[0].name : null
}

output "marketing_fqdn" {
  value = length(aws_route53_record.marketing) > 0 ? aws_route53_record.marketing[0].name : null
}
