variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "allowed_security_group_ids" {
  description = "Security groups permitted to reach Postgres (Fargate tasks, Connection Pooler)."
  type        = list(string)
}

variable "postgres_version" {
  description = "Major version only (e.g. \"16\", not \"16.4\") -- RDS resolves the latest available minor at creation time and auto_minor_version_upgrade keeps it current, so this never needs to track a specific minor that AWS may later deprecate (see aws_db_instance.writer)."
  type        = string
  default     = "16"
}

variable "postgres_parameter_group_family" {
  type    = string
  default = "postgres16"
}

variable "instance_class" {
  type    = string
  default = "db.r6g.large"
}

variable "replica_instance_class" {
  type    = string
  default = "db.r6g.large"
}

variable "read_replica_count" {
  description = "Number of read replicas provisioned from launch (architecture.md: read replicas from launch, not a later addition)."
  type        = number
  default     = 1
}

variable "allocated_storage_gb" {
  type    = number
  default = 100
}

variable "max_allocated_storage_gb" {
  type    = number
  default = 1000
}

variable "database_name" {
  type    = string
  default = "deduke"
}

variable "master_username" {
  type    = string
  default = "deduke_admin"
}

variable "multi_az" {
  description = "Multi-AZ standby — a reliability baseline per architecture.md, not optional."
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
