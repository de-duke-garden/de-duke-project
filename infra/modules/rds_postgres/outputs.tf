output "writer_endpoint" {
  value = aws_db_instance.writer.address
}

output "writer_secret_arn" {
  description = "ARN of the AWS-managed master user secret (auto-created; populate nothing manually)."
  value       = aws_db_instance.writer.master_user_secret[0].secret_arn
}

output "read_replica_endpoints" {
  value = [for r in aws_db_instance.read_replica : r.address]
}

output "db_security_group_id" {
  value = aws_security_group.db.id
}
