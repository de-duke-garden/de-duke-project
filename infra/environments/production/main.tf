# De-Duke -- Production environment
# Wires together every infra module per architecture.md. This is the sizing
# baseline that Staging (../staging/main.tf) is required to mirror per the
# Load Testing & Performance Validation section -- if capacity numbers change
# here, update staging/main.tf to match in the same change, or Staging's load
# test results stop being representative of Production.

module "networking" {
  source = "../../modules/networking"
  # See staging/main.tf's identical override for why this is required --
  # each environment gets its own /16 matching its own availability_zones
  # CIDRs (development: module default 10.0.0.0/16, staging: 10.1.0.0/16,
  # production: 10.2.0.0/16).
  vpc_cidr           = "10.2.0.0/16"
  environment        = var.environment
  availability_zones = var.availability_zones
  tags               = local.common_tags
}

# NOT module "ecr" -- see staging/main.tf's identical comment. The registry
# is shared/global across every environment; development's Terraform state
# already owns creating it.
data "aws_ecr_repository" "backend" {
  name = "de-duke/backend-api"
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
  # TEMPORARY cost-minimization pass (all three environments, same date) --
  # deliberately NOT Multi-AZ per architecture.md right now. Production is
  # not live yet (production is commented out of the active deploy matrix
  # in backend-deploy.yml / infra-terraform.yml, and this environment
  # carries no real traffic pre-launch), so paying for Multi-AZ automatic
  # failover before there's anything to fail over for is pure waste.
  # MUST restore node_type = "cache.r6g.large", num_cache_clusters = 2
  # before this environment is re-enabled in the deploy matrix / goes live
  # -- see this file's own header comment on Staging mirroring Production.
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
  # TEMPORARY cost-minimization pass, same rationale as module "cache"
  # above -- multi_az/instance_class/allocated_storage_gb are all
  # downsized below architecture.md's Scaling Strategy baseline
  # ("Multi-AZ standby ... not optional", "read replicas from launch").
  # read_replica_count was also already dropped to 0 for the same RDS
  # manage_master_user_password limitation documented in
  # staging/main.tf's identical comment.
  # MUST restore multi_az = true, read_replica_count = 1, instance_class /
  # replica_instance_class = "db.r6g.xlarge", allocated_storage_gb = 500
  # before this environment goes live -- right now there is no failover
  # capacity and no read-replica headroom.
  multi_az               = false
  read_replica_count     = 0
  instance_class         = "db.t4g.micro"
  replica_instance_class = "db.t4g.micro"
  allocated_storage_gb   = 20
  deletion_protection    = true
  tags                   = local.common_tags
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
