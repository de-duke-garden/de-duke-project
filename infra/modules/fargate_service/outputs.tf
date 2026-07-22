output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_arn" {
  value = aws_lb.this.arn
}

# Route53 alias records target an ALB by (dns_name, zone_id) pair, not dns_name
# alone -- consumed by modules/dns's aws_route53_record.api alias block.
output "alb_zone_id" {
  value = aws_lb.this.zone_id
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "db_proxy_endpoint" {
  value = aws_db_proxy.this.endpoint
}
