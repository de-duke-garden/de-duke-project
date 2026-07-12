variable "environment" { type = string }
variable "log_level" {
  description = "Root logger level (app/core/logging_config.py) -- INFO in every environment unless a specific noisy-debug investigation needs more."
  type        = string
  default     = "INFO"
}
variable "aws_region" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "private_subnet_ids" { type = list(string) }

variable "alb_security_group_id" {
  description = "Security group for the ALB, created at the environment root to avoid a dependency cycle with RDS/Redis ingress rules."
  type        = string
}

variable "service_security_group_id" {
  description = "Security group for the Fargate tasks themselves, created at the environment root for the same reason."
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM cert for the ALB HTTPS listener. Left unset until a domain is registered."
  type        = string
}

variable "ecr_repository_url" { type = string }
variable "image_tag" {
  description = "Tag of the real application image to deploy. Left as the default empty string before CI has ever pushed one (e.g. the very first `terraform apply` for a fresh environment) -- see the placeholder-image logic in main.tf for why that case is handled explicitly rather than defaulting to a nonexistent `:latest` tag."
  type        = string
  default     = ""
}

variable "execution_role_arn" { type = string }
variable "task_role_arn" { type = string }

variable "app_secret_arn" { type = string }
variable "db_master_secret_arn" { type = string }
variable "db_writer_identifier" { type = string }
variable "db_proxy_role_arn" { type = string }

# File Storage Service (S3 + CDN, infra/modules/s3_cdn) -- plain env vars,
# not secrets, consumed by app/core/config.py's Settings.media_bucket_name/
# media_cdn_domain (app/core/storage.py's S3 client + CDN URL builder).
variable "media_bucket_name" { type = string }
variable "media_cdn_domain" { type = string }

# module.cache's primary_endpoint output (infra/modules/redis/outputs.tf) --
# threaded through so this module can set REDIS_URL in the container's
# environment. See this module's main.tf REDIS_URL comment for why this
# was previously missing entirely.
variable "redis_endpoint" { type = string }

# FEAT-001 phone OTP delivery (app/services/sms_service.py, Amazon SNS) --
# not a secret, no separate vendor account; a plain string identifying
# this app's registered SNS Sender ID.
variable "aws_sns_sender_id" {
  type    = string
  default = "REPLACE_ME"
}

variable "task_cpu" {
  type    = number
  default = 512
}
variable "task_memory" {
  type    = number
  default = 1024
}

variable "min_task_count" {
  type    = number
  default = 2
}
variable "max_task_count" {
  type    = number
  default = 20
}
variable "cpu_target_percent" {
  type    = number
  default = 60
}

variable "deregistration_delay_seconds" {
  description = "Connection draining window on scale-in/deploy (architecture.md)."
  type        = number
  default     = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
