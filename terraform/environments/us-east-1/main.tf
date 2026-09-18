locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Region      = var.aws_region
    ManagedBy   = "Terraform"
  }
}

# ==============================================================================
# 1. NETWORKING: VPC & SUBNETS (3-TIER ARCHITECTURE)
# ==============================================================================
module "vpc" {
  source = "../../modules/vpc"

  project_name             = var.project_name
  environment              = var.environment
  vpc_cidr                 = var.vpc_cidr
  availability_zones       = var.availability_zones
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs  = var.private_db_subnet_cidrs
  single_nat_gateway       = var.single_nat_gateway
  common_tags              = local.common_tags
}

# ==============================================================================
# 2. NETWORK ACCESS CONTROL LISTS (NACLs)
# ==============================================================================
module "nacl" {
  source = "../../modules/nacl"

  project_name             = var.project_name
  environment              = var.environment
  vpc_id                   = module.vpc.vpc_id
  vpc_cidr                 = module.vpc.vpc_cidr
  public_subnet_ids        = module.vpc.public_subnet_ids
  private_app_subnet_ids   = module.vpc.private_app_subnet_ids
  private_db_subnet_ids    = module.vpc.private_db_subnet_ids
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  app_port                 = var.app_port
  common_tags              = local.common_tags
}

# ==============================================================================
# 3. SECURITY GROUPS (CHAINED PERIMETER CONTROLS)
# ==============================================================================
module "security_groups" {
  source = "../../modules/security_groups"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = module.vpc.vpc_cidr
  app_port     = var.app_port
  common_tags  = local.common_tags
}

# ==============================================================================
# 4. OBJECT STORAGE: S3 BUCKET (ASSETS & UPLOADS)
# ==============================================================================
module "s3" {
  source = "../../modules/s3"

  project_name   = var.project_name
  environment    = var.environment
  bucket_purpose = "assets"
  force_destroy  = false
  common_tags    = local.common_tags
}

# ==============================================================================
# 5. DATABASE: AMAZON RDS MYSQL (MULTI-AZ & SECRETS MANAGER)
# ==============================================================================
module "rds_mysql" {
  source = "../../modules/rds_mysql"

  project_name          = var.project_name
  environment           = var.environment
  private_db_subnet_ids = module.vpc.private_db_subnet_ids
  rds_security_group_id = module.security_groups.rds_security_group_id
  db_instance_class     = var.db_instance_class
  database_name         = var.database_name
  db_username           = var.db_username
  multi_az              = var.multi_az
  common_tags           = local.common_tags
}

# ==============================================================================
# 6. IAM: EC2 INSTANCE PROFILE (SSM, SECRETS, S3, CLOUDWATCH)
# ==============================================================================
module "iam" {
  source = "../../modules/iam"

  project_name        = var.project_name
  environment         = var.environment
  secrets_manager_arn = module.rds_mysql.db_secrets_manager_arn
  s3_bucket_arn       = module.s3.bucket_arn
  common_tags         = local.common_tags
}

# ==============================================================================
# 7. ROUTE 53 & ACM CERTIFICATE (HTTPS)
# ==============================================================================
module "route53" {
  source = "../../modules/route53"

  project_name           = var.project_name
  environment            = var.environment
  aws_region             = var.aws_region
  enable_route53_and_acm = var.enable_route53_and_acm
  domain_name            = var.domain_name
  subdomain              = var.subdomain
  hosted_zone_id         = var.hosted_zone_id
  alb_dns_name           = module.alb_waf.alb_dns_name
  alb_zone_id            = module.alb_waf.alb_zone_id
  common_tags            = local.common_tags
}

# ==============================================================================
# 8. LOAD BALANCING & WAF PERIMETER DEFENSE
# ==============================================================================
module "alb_waf" {
  source = "../../modules/alb_waf"

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_security_group_id = module.security_groups.alb_security_group_id
  app_port              = var.app_port
  certificate_arn       = module.route53.certificate_arn
  enable_waf            = true
  common_tags           = local.common_tags
}

# ==============================================================================
# 9. COMPUTE: AUTO SCALING GROUP & LAUNCH TEMPLATE
# ==============================================================================
module "asg" {
  source = "../../modules/asg"

  project_name           = var.project_name
  environment            = var.environment
  aws_region             = var.aws_region
  instance_type          = var.instance_type
  instance_profile_arn   = module.iam.instance_profile_arn
  ec2_security_group_id  = module.security_groups.ec2_security_group_id
  private_app_subnet_ids = module.vpc.private_app_subnet_ids
  target_group_arn       = module.alb_waf.target_group_arn
  desired_capacity       = var.desired_capacity
  minimum_capacity       = var.minimum_capacity
  maximum_capacity       = var.maximum_capacity
  app_port               = var.app_port
  db_secret_arn          = module.rds_mysql.db_secrets_manager_arn
  db_endpoint            = module.rds_mysql.db_instance_endpoint
  s3_bucket_name         = module.s3.bucket_id
  common_tags            = local.common_tags
}

# ==============================================================================
# 10. OBSERVABILITY: CLOUDWATCH LOGS, METRIC ALARMS & DASHBOARD
# ==============================================================================
module "cloudwatch" {
  source = "../../modules/cloudwatch"

  project_name   = var.project_name
  environment    = var.environment
  aws_region     = var.aws_region
  asg_name       = module.asg.asg_name
  alb_arn_suffix = module.alb_waf.alb_arn
  db_instance_id = module.rds_mysql.db_instance_id
  common_tags    = local.common_tags
}

# ==============================================================================
# 11. IAM ACCESS MANAGEMENT (1 TEAM LEAD + 10 CLIENTS)
# ==============================================================================
module "iam_access" {
  source = "../../modules/iam_access"

  project_name      = var.project_name
  create_iam_access = var.create_iam_access
  s3_bucket_arn     = module.s3.bucket_arn
  common_tags       = local.common_tags
}
