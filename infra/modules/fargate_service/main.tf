# De-Duke -- Backend API Service module
# Stateless FastAPI containers on AWS Fargate behind an ALB, target-tracking
# auto-scaling, connection draining on scale-in, and an RDS Proxy acting as
# the Database Connection Pooler (architecture.md Scaling Strategy).

resource "aws_ecs_cluster" "this" {
  name = "${var.environment}-de-duke-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = var.tags
}

resource "aws_lb" "this" {
  name               = "${var.environment}-de-duke-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  tags = var.tags
}

resource "aws_lb_target_group" "backend" {
  name        = "${var.environment}-de-duke-api-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health/ready"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
  }

  deregistration_delay = var.deregistration_delay_seconds

  tags = var.tags
}

locals {
  # var.acm_certificate_arn is documented as "left unset until a domain is
  # registered" -- the same "nothing real yet" bootstrap case as
  # local.using_placeholder_image below, just for the ALB instead of the
  # task definition. An HTTPS listener requires a real certificate to even
  # be created, so it must be conditional on one existing.
  has_certificate = var.acm_certificate_arn != ""
}

resource "aws_lb_listener" "https" {
  count = local.has_certificate ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

# Always created, unlike the HTTPS listener above -- otherwise a fresh
# environment with no certificate yet would have an ALB with no listener
# at all. Forwards directly to the target group until a certificate
# exists; once one is supplied, this switches to a redirect so plain HTTP
# traffic is never served.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = local.has_certificate ? "redirect" : "forward"

    dynamic "redirect" {
      for_each = local.has_certificate ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    target_group_arn = local.has_certificate ? null : aws_lb_target_group.backend.arn
  }
}

resource "aws_db_proxy" "this" {
  name                   = "${var.environment}-de-duke-db-proxy"
  engine_family          = "POSTGRESQL"
  role_arn               = var.db_proxy_role_arn
  vpc_subnet_ids         = var.private_subnet_ids
  vpc_security_group_ids = [var.service_security_group_id]

  auth {
    auth_scheme = "SECRETS"
    secret_arn  = var.db_master_secret_arn
  }

  tags = var.tags
}

resource "aws_db_proxy_default_target_group" "this" {
  db_proxy_name = aws_db_proxy.this.name

  connection_pool_config {
    max_connections_percent      = 90
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "writer" {
  db_proxy_name          = aws_db_proxy.this.name
  target_group_name      = aws_db_proxy_default_target_group.this.name
  db_instance_identifier = var.db_writer_identifier
}

locals {
  # Terraform only provisions infrastructure -- it never builds or pushes a
  # container image itself (that is .github/workflows/backend-deploy.yml's
  # job, via the AWS CLI/Docker). Before that workflow has ever run against
  # a fresh environment, var.image_tag is "" and no image exists at
  # "${ecr_repository_url}:<anything>" yet, so pointing the task definition
  # at the (nonexistent) ECR tag would leave the service stuck endlessly
  # failing to pull an image. Point at a small, always-available public
  # placeholder instead for that one case -- the ALB health check
  # (/health/ready) will legitimately 404 against it until the real app
  # deploys, which is expected and harmless: aws_ecs_service below does not
  # set wait_for_steady_state, so this never blocks `terraform apply`
  # itself. The remapped command just moves nginx's listener from its
  # image default (80) to this service's fixed container port (8000).
  using_placeholder_image = var.image_tag == ""
  container_image         = local.using_placeholder_image ? "public.ecr.aws/nginx/nginx:latest" : "${var.ecr_repository_url}:${var.image_tag}"
}

# The awslogs driver below does not create this log group itself -- it
# only creates the log stream inside it, and fails outright
# (ResourceInitializationError / ResourceNotFoundException) if the group
# doesn't already exist. Every task would otherwise crash-loop at startup.
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/de-duke/${var.environment}/backend-api"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_ecs_task_definition" "backend" {
  family                   = "${var.environment}-de-duke-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([merge(
    {
      name         = "backend-api"
      image        = local.container_image
      portMappings = [{ containerPort = 8000, protocol = "tcp" }]
      environment = [
        { name = "DEDUKE_ENVIRONMENT", value = var.environment },
        { name = "LOG_LEVEL", value = var.log_level },
        { name = "DB_PROXY_ENDPOINT", value = aws_db_proxy.this.endpoint },
        { name = "MEDIA_BUCKET_NAME", value = var.media_bucket_name },
        { name = "MEDIA_CDN_DOMAIN", value = var.media_cdn_domain },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "AWS_SNS_SENDER_ID", value = var.aws_sns_sender_id },
      ]
      secrets = [
        { name = "APP_SECRETS", valueFrom = var.app_secret_arn },
        { name = "DB_CREDENTIALS", valueFrom = var.db_master_secret_arn },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "backend-api"
        }
      }
    },
    local.using_placeholder_image ? {
      command = ["sh", "-c", "sed -i 's/listen  *80;/listen 8000;/' /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"]
    } : {}
  )])

  tags = var.tags
}

resource "aws_ecs_service" "backend" {
  name            = "${var.environment}-de-duke-api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.min_task_count
  launch_type     = "FARGATE"

  # Enables ECS Exec (the console's "Connect" button / `aws ecs
  # execute-command`) -- also requires the task role to have the
  # ssmmessages:* permissions granted in environments/development/iam.tf's
  # task_exec_ssm policy. Without both, Connect stays disabled.
  enable_execute_command = true

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = [var.service_security_group_id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend-api"
    container_port   = 8000
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # http always exists; https only when a certificate is configured (see
  # local.has_certificate above) -- depends_on requires a static list, but
  # referencing the whole (possibly count = 0) https resource here still
  # correctly depends on all of its instances, however many exist.
  depends_on = [aws_lb_listener.http, aws_lb_listener.https]
  tags       = var.tags
}

resource "aws_appautoscaling_target" "backend" {
  max_capacity       = var.max_task_count
  min_capacity       = var.min_task_count
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.backend.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.environment}-de-duke-api-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.backend.resource_id
  scalable_dimension = aws_appautoscaling_target.backend.scalable_dimension
  service_namespace  = aws_appautoscaling_target.backend.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.cpu_target_percent
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
