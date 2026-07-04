# IAM roles required by the Fargate service module: task execution role (pulls
# image from ECR, writes logs, reads secrets), task role (the app's own AWS
# permissions at runtime), and the RDS Proxy's IAM role.

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${var.environment}-de-duke-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "task_execution_secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [module.secrets.app_secret_arn, module.rds.writer_secret_arn]
  }
}

resource "aws_iam_role_policy" "task_execution_secrets" {
  name   = "${var.environment}-de-duke-task-execution-secrets"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution_secrets.json
}

resource "aws_iam_role" "task" {
  name               = "${var.environment}-de-duke-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

# Application-level runtime permissions (S3 media bucket, SQS task queue).
# Kept minimal and expanded deliberately per feature, not broadened by default.
data "aws_iam_policy_document" "task_runtime" {
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${module.media.bucket_name}/*"]
  }
  statement {
    actions   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [module.tasks_queue.queue_arn]
  }
}

resource "aws_iam_role_policy" "task_runtime" {
  name   = "${var.environment}-de-duke-task-runtime"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_runtime.json
}

data "aws_iam_policy_document" "db_proxy_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "db_proxy" {
  name               = "${var.environment}-de-duke-db-proxy"
  assume_role_policy = data.aws_iam_policy_document.db_proxy_assume.json
}

data "aws_iam_policy_document" "db_proxy_secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [module.rds.writer_secret_arn]
  }
}

resource "aws_iam_role_policy" "db_proxy_secrets" {
  name   = "${var.environment}-de-duke-db-proxy-secrets"
  role   = aws_iam_role.db_proxy.id
  policy = data.aws_iam_policy_document.db_proxy_secrets.json
}
