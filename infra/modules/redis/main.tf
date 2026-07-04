# De-Duke — Caching Layer module
# Managed Redis (Multi-AZ, automatic failover) — deliberately its own instance,
# not shared with the Task Queue (architecture.md: avoids noisy-neighbor risk
# between caching hot-spots and background job processing).

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.environment}-de-duke-cache-subnets"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "cache" {
  name_prefix = "${var.environment}-de-duke-cache-"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from Backend API Service"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.environment}-de-duke-cache"
  description          = "De-Duke Caching Layer (hot search results, embeddings, rate-limit counters)"

  engine         = "redis"
  engine_version = var.redis_version
  node_type      = var.node_type

  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = var.num_cache_clusters > 1
  multi_az_enabled           = var.num_cache_clusters > 1

  subnet_group_name = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.cache.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true

  tags = var.tags
}
