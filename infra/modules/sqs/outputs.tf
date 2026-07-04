output "queue_url" {
  value = aws_sqs_queue.tasks.url
}

output "queue_arn" {
  value = aws_sqs_queue.tasks.arn
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}
