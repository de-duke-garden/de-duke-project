variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "allowed_security_group_ids" { type = list(string) }

variable "redis_version" {
  type    = string
  default = "7.1"
}

variable "node_type" {
  type    = string
  default = "cache.r6g.large"
}

variable "num_cache_clusters" {
  description = "Number of cache nodes. >1 enables Multi-AZ automatic failover (architecture.md requirement)."
  type        = number
  default     = 2
}

variable "tags" {
  type    = map(string)
  default = {}
}
