# De-Duke -- Staging environment
# Wires together every infra module per architecture.md. Sized IDENTICALLY to
# Production (same instance types, replica counts, auto-scaling config) per
# the Load Testing & Performance Validation section's requirement that load
# tests "run against a dedicated Staging environment provisioned identically
# to Production ... never against an under-scaled Staging that can't reveal
# real bottlenecks." The only intentional differences from Production are
# deletion_protection (off here, so synthetic load-test data/state can be
# torn down and reseeded) and RDS deletion_protection -- never capacity.

module "networking" {
  source = "../../modules/networking"
  # Overridden from the module's 10.0.0.0/16 default -- staging's own
  # availability_zones (below) carve subnets out of 10.1.0.0/0, which falls
  # outside that default block and fails subnet creation
  # (InvalidSubnet.Range) if vpc_cidr isn't also overridden to match. Each
  # environment gets its own /16 (development implicitly uses the module's
  # 10.0.0.0/16 default, staging is 10.1.0.0/16, production is 10.2.0.0/16)
  # so there's never a collision if these VPCs are ever peered.
  vpc_cidr           = "10.1.0.0/16"
  environment        = var.environment
  availability_zones = var.availability_zones
  tags               = local.common_tags
}

# NOT module "ecr" -- deliberately. infra/modules/ecr/main.tf names the
# repository "de-duke/backend-api" unconditionally (not templated per
# environment), so it is a single registry SHARED across every
# environment's images (see backend-deploy.yml: the same repo, tagged by
# Git SHA, deployed to whichever environment's task definition references
# that tag). `development`'s Terraform state already owns creating this
# resource; a second `module "ecr"` block here would try to create the same
# repository a second time and fail with RepositoryAlreadyExistsException,
# which is exactly what happened the first time this was attempted. Read it
# as data instead.
data "aws_ecr_repository" "backend" {
  name = "de-duke/backend-api"
}

module "secrets" {
  source      = "../../modules/secrets"
  environment = var.environment
  tags        = local.common_tags
}

module "media" {
  source         = "../../modules/s3_cdn"
  environment    = var.environment
  account_suffix = var.aws_account_suffix
  tags           = local.common_tags
}

module "tasks_queue" {
  source      = "../../modules/sqs"
  environment = var.environment
  tags        = local.common_tags
}

module "cache" {
  source                     = "../../modules/redis"
  environment                = var.environment
  vpc_id                     = module.networking.vpc_id
  private_subnet_ids         = module.networking.private_subnet_ids
  allowed_security_group_ids = [aws_security_group.backend_service.id]
  # Multi-AZ automatic failover, matching Production -- see load_tests/README.md
  # Failover (chaos) test, which depends on this actually being Multi-AZ here.
  node_type          = "cache.r6g.large"
  num_cache_clusters = 2
  tags               = local.common_tags
}

module "rds" {
  source                     = "../../modules/rds_postgres"
  environment                = var.environment
  vpc_id                     = module.networking.vpc_id
  private_subnet_ids         = module.networking.private_subnet_ids
  allowed_security_group_ids = [aws_security_group.backend_service.id]
  # Matches Production's topology (Multi-AZ) -- read_replica_count is
  # TEMPORARILY 0, not the originally-intended 1: RDS does not support read
  # replicas on a Postgres instance using AWS-managed master password
  # (manage_master_user_password, see modules/rds_postgres/main.tf), which
  # this module uses by design. Discovered when the real `terraform apply`
  # against this environment failed with "Creating read replicas for
  # source instance with engine postgres where ManageMasterUserPassword is
  # enabled is not supported." `development` never hit this because it
  # already runs read_replica_count = 0.
  #
  # TODO before the real Phase 1 launch-gate run: switch
  # modules/rds_postgres to a self-managed master password (stored in
  # modules/secrets, same pattern as every other credential in this repo)
  # instead of manage_master_user_password, then restore
  # read_replica_count = 1 here so Priority Scenario 1 (Search & Discovery
  # under load, load_tests/README.md) actually exercises read-replica
  # routing and replica lag as originally intended -- right now that
  # scenario's replica-lag assertions are meaningless against a
  # single-instance database.
  multi_az               = true
  read_replica_count     = 0
  instance_class         = "db.r6g.xlarge"
  replica_instance_class = "db.r6g.xlarge"
  allocated_storage_gb   = 500
  # Deletion protection off (unlike Production) -- Staging's DB is
  # periodically wiped and reseeded with fresh synthetic data at target scale
  # (see load_tests/seed/).
  deletion_protection = false
  tags                = local.common_tags
}

module "backend" {
  source = "../../modules/fargate_service"

  environment               = var.environment
  aws_region                = var.aws_region
  vpc_id                    = module.networking.vpc_id
  public_subnet_ids         = module.networking.public_subnet_ids
  private_subnet_ids        = module.networking.private_subnet_ids
  acm_certificate_arn       = var.acm_certificate_arn
  alb_security_group_id     = aws_security_group.alb.id
  service_security_group_id = aws_security_group.backend_service.id

  ecr_repository_url = data.aws_ecr_repository.backend.repository_url
  image_tag          = var.image_tag

  execution_role_arn = aws_iam_role.task_execution.arn
  task_role_arn      = aws_iam_role.task.arn
  db_proxy_role_arn  = aws_iam_role.db_proxy.arn

  app_secret_arn       = module.secrets.app_secret_arn
  db_master_secret_arn = module.rds.writer_secret_arn
  db_writer_identifier = "${var.environment}-de-duke-primary"

  media_bucket_name = module.media.bucket_name
  media_cdn_domain  = module.media.cdn_domain_name
  redis_endpoint    = module.cache.primary_endpoint

  # Matches Production's auto-scaling ceiling/floor so Priority Scenario 7
  # (Fargate scale-out under the Connection Pooler) and the Spike test
  # actually validate real scale-out behavior, not Development's toy footprint.
  min_task_count = 4
  max_task_count = 40
  task_cpu       = 1024
  task_memory    = 2048

  tags = local.common_tags
}

module "waf" {
  source      = "../../modules/waf"
  environment = var.environment
  alb_arn     = module.backend.alb_arn
  tags        = local.common_tags
}
