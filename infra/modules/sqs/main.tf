# De-Duke — Task Queue module (Amazon SQS + dead-letter queue)
# Durable, at-least-once delivery for notifications, verification callbacks,
# receipt generation, commission calculation, and hold-expiry jobs.
# Deliberately separate from the Caching Layer (Redis) per architecture.md.

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.environment}-de-duke-tasks-dlq"
  message_retention_seconds = var.dlq_retention_seconds
  tags                      = var.tags
}

resource "aws_sqs_queue" "tasks" {
  name                       = "${var.environment}-de-duke-tasks"
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = var.tags
}
