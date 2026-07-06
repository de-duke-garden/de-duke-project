# De-Duke — Primary Database module
# PostgreSQL with PostGIS + pgvector extensions (schema.md, architecture.md).
# Ships with a Multi-AZ standby and read replicas from launch (architecture.md
# Scaling Strategy: "read replicas from launch, not as a later addition").

resource "aws_db_subnet_group" "this" {
  name       = "${var.environment}-de-duke-db-subnets"
  subnet_ids = var.private_subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "db" {
  name_prefix = "${var.environment}-de-duke-db-"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Postgres from Backend API Service / Connection Pooler"
    from_port       = 5432
    to_port         = 5432
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

# RDS-managed master password: rotated/held in a Secrets Manager secret AWS
# creates and owns automatically (manage_master_user_password = true) — this
# is the "second secret, automatically defined by AWS" referenced in AGENTS.md.
resource "aws_db_instance" "writer" {
  identifier     = "${var.environment}-de-duke-primary"
  engine         = "postgres"
  engine_version = var.postgres_version
  instance_class = var.instance_class

  # var.postgres_version is major-version-only ("16", not "16.4") so RDS
  # always resolves the latest available minor at creation time --
  # pinning an exact minor breaks the moment AWS deprecates it (as
  # happened with the previously-hardcoded 16.4). Let RDS keep picking up
  # new minors automatically rather than re-pinning by hand each time.
  auto_minor_version_upgrade = true

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.database_name
  username = var.master_username

  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]

  multi_az            = var.multi_az
  publicly_accessible = false

  backup_retention_period = var.backup_retention_days
  deletion_protection     = var.deletion_protection
  skip_final_snapshot     = !var.deletion_protection

  # PostGIS + pgvector are enabled via a parameter group loading both
  # extensions, and `CREATE EXTENSION` run once by the app's first migration.
  parameter_group_name = aws_db_parameter_group.this.name

  tags = var.tags
}

resource "aws_db_parameter_group" "this" {
  name   = "${var.environment}-de-duke-pg-params"
  family = var.postgres_parameter_group_family

  # PostGIS and pgvector are both enabled purely via `CREATE EXTENSION`
  # (see the comment on aws_db_instance.writer above) -- neither needs (or
  # for pgvector, is even a valid) shared_preload_libraries entry on RDS.
  # Only extensions that genuinely require preloading (e.g.
  # pg_stat_statements, for query performance monitoring) belong here.
  #
  # shared_preload_libraries is a "static" RDS parameter -- it only takes
  # effect after an instance reboot, so it must use apply_method =
  # "pending-reboot" (the default "immediate" is only valid for dynamic
  # parameters and RDS rejects it outright for this one).
  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  tags = var.tags
}

resource "aws_db_instance" "read_replica" {
  count = var.read_replica_count

  identifier          = "${var.environment}-de-duke-replica-${count.index}"
  replicate_source_db = aws_db_instance.writer.identifier
  instance_class      = var.replica_instance_class
  publicly_accessible = false
  storage_encrypted   = true

  tags = var.tags
}
