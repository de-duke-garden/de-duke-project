output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_arn" {
  value = aws_lb.this.arn
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "db_proxy_endpoint" {
  value = aws_db_proxy.this.endpoint
}
