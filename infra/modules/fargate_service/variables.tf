variable "environment" { type = string }
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
  type    = string
  default = "latest"
}

variable "execution_role_arn" { type = string }
variable "task_role_arn" { type = string }

variable "app_secret_arn" { type = string }
variable "db_master_secret_arn" { type = string }
variable "db_writer_identifier" { type = string }
variable "db_proxy_role_arn" { type = string }

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
