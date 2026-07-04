# De-Duke -- Development environment
# Wires together every infra module per architecture.md. This file defines
# the resources only -- nothing here is applied until `terraform apply` is
# explicitly run by an operator with valid AWS/GCP credentials.

module "networking" {
  source             = "../../modules/networking"
  environment        = var.environment
  availability_zones = var.availability_zones
  tags               = local.common_tags
}

module "ecr" {
  source = "../../modules/ecr"
  tags   = local.common_tags
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
  # Development is single-node (cheaper); staging/production use >1 for
  # Multi-AZ automatic failover per architecture.md.
  num_cache_clusters = 1
  tags               = local.common_tags
}

module "rds" {
  source                     = "../../modules/rds_postgres"
  environment                = var.environment
  vpc_id                     = module.networking.vpc_id
  private_subnet_ids         = module.networking.private_subnet_ids
  allowed_security_group_ids = [aws_security_group.backend_service.id]
  # Development runs single-AZ, no replicas, smallest instance class to
  # control cost -- staging/production override these per architecture.md.
  multi_az            = false
  read_replica_count  = 0
  instance_class      = "db.t4g.medium"
  deletion_protection = false
  tags                = local.common_tags
}

module "backend" {
  source = "../../modules/fargate_service"

  environment         = var.environment
  aws_region          = var.aws_region
  vpc_id              = module.networking.vpc_id
  public_subnet_ids   = module.networking.public_subnet_ids
  private_subnet_ids  = module.networking.private_subnet_ids
  acm_certificate_arn       = var.acm_certificate_arn
  alb_security_group_id     = aws_security_group.alb.id
  service_security_group_id = aws_security_group.backend_service.id

  ecr_repository_url = module.ecr.repository_url

  execution_role_arn = aws_iam_role.task_execution.arn
  task_role_arn      = aws_iam_role.task.arn
  db_proxy_role_arn  = aws_iam_role.db_proxy.arn

  app_secret_arn        = module.secrets.app_secret_arn
  db_master_secret_arn  = module.rds.writer_secret_arn
  db_writer_identifier  = "${var.environment}-de-duke-primary"

  # Development runs the smallest viable footprint.
  min_task_count = 1
  max_task_count = 2
  task_cpu       = 256
  task_memory    = 512

  tags = local.common_tags
}

module "waf" {
  source      = "../../modules/waf"
  environment = var.environment
  alb_arn     = module.backend.alb_arn
  tags        = local.common_tags
}
