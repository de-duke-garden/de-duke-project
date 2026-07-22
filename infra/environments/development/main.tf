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
  source                        = "../../modules/s3_cdn"
  environment                   = var.environment
  account_suffix                = var.aws_account_suffix
  cdn_domain_name               = local.cdn_fqdn
  acm_certificate_arn_us_east_1 = var.cdn_acm_certificate_arn
  tags                          = local.common_tags
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
  # Cost-minimization pass (all three environments, same date) -- smallest
  # burstable node, single instance, no Multi-AZ failover. Pre-launch,
  # traffic on every environment is near-zero, so paying for
  # architecture.md's target-scale sizing here is pure waste. Upgrade back
  # to a production-representative node_type/num_cache_clusters before the
  # Phase 1 launch-gate load test run (load_tests/README.md) -- see that
  # file's Cadence section.
  node_type          = "cache.t4g.micro"
  num_cache_clusters = 1
  tags               = local.common_tags
}

module "rds" {
  source                     = "../../modules/rds_postgres"
  environment                = var.environment
  vpc_id                     = module.networking.vpc_id
  private_subnet_ids         = module.networking.private_subnet_ids
  allowed_security_group_ids = [aws_security_group.backend_service.id]
  # Development runs single-AZ, no replicas, smallest viable instance class
  # and storage to control cost -- see module "cache" above's identical
  # cost-minimization note. Upgrade before the launch-gate run.
  multi_az             = false
  read_replica_count   = 0
  instance_class       = "db.t4g.micro"
  allocated_storage_gb = 20
  deletion_protection  = false
  tags                 = local.common_tags
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

  ecr_repository_url = module.ecr.repository_url
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

# Existing, externally-managed Route53 hosted zone -- looked up by name
# (not imported into this state), so this config can create/update the
# subdomain records below without ever having the ability to delete or
# recreate the zone itself. See environments/global for the one-time
# ALB-facing cert bootstrap that this environment's acm_certificate_arn
# variable depends on.
data "aws_route53_zone" "primary" {
  name         = local.domain_name
  private_zone = false
}

module "dns" {
  source = "../../modules/dns"

  zone_id = data.aws_route53_zone.primary.zone_id

  api_fqdn     = local.api_fqdn
  alb_dns_name = module.backend.alb_dns_name
  alb_zone_id  = module.backend.alb_zone_id

  # Only created once the CloudFront distribution actually has a matching
  # alias configured (module.media.cdn_domain_name reflects the real
  # *.cloudfront.net domain either way, but the alias record must not
  # exist until CloudFront itself recognizes cdn_fqdn as one of its own
  # aliases -- see modules/s3_cdn's has_custom_domain gate).
  create_cdn_record = var.cdn_acm_certificate_arn != ""
  cdn_fqdn          = local.cdn_fqdn
  cdn_domain_name   = module.media.cdn_domain_name
}
