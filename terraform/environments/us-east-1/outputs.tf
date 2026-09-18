# ==============================================================================
# STAYDRIV US-EAST-1 INFRASTRUCTURE OUTPUTS
# ==============================================================================

# --- VPC & Subnets ---
output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "List of Public Subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "List of Private Application Subnet IDs"
  value       = module.vpc.private_app_subnet_ids
}

output "private_db_subnet_ids" {
  description = "List of Private Database Subnet IDs"
  value       = module.vpc.private_db_subnet_ids
}

# --- Application Load Balancer ---
output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = module.alb_waf.alb_dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = module.alb_waf.alb_arn
}

# --- Amazon RDS MySQL ---
output "rds_endpoint" {
  description = "Connection endpoint for Amazon RDS MySQL instance (Host:Port)"
  value       = module.rds_mysql.db_instance_endpoint
}

output "rds_instance_address" {
  description = "Host address of the RDS MySQL instance"
  value       = module.rds_mysql.db_instance_address
}

output "rds_database_name" {
  description = "Database name"
  value       = module.rds_mysql.db_name
}

output "rds_secrets_manager_arn" {
  description = "Secrets Manager Secret ARN containing database master credentials"
  value       = module.rds_mysql.db_secrets_manager_arn
}

# --- S3 Storage ---
output "s3_bucket_name" {
  description = "Name of the S3 bucket for StayDriv application assets"
  value       = module.s3.bucket_id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = module.s3.bucket_arn
}

# --- Security Groups ---
output "security_group_ids" {
  description = "Map of all created Security Group IDs"
  value = {
    alb = module.security_groups.alb_security_group_id
    ec2 = module.security_groups.ec2_security_group_id
    rds = module.security_groups.rds_security_group_id
  }
}

# --- Auto Scaling Group & Monitoring ---
output "asg_name" {
  description = "Auto Scaling Group Name"
  value       = module.asg.asg_name
}

output "cloudwatch_dashboard" {
  description = "Name of the operational CloudWatch dashboard"
  value       = module.cloudwatch.dashboard_name
}

# --- IAM Access Governance (Team Lead & Clients) ---
output "team_lead_user_name" {
  description = "IAM User Name for Team Lead"
  value       = module.iam_access.team_lead_user_name
}

output "team_lead_user_arn" {
  description = "IAM User ARN for Team Lead"
  value       = module.iam_access.team_lead_user_arn
}

output "team_lead_secret_arn" {
  description = "Secrets Manager ARN storing Team Lead credentials"
  value       = module.iam_access.team_lead_secret_arn
}

output "client_user_names" {
  description = "List of IAM User Names for the 10 Clients"
  value       = module.iam_access.client_user_names
}

output "client_user_arns" {
  description = "List of IAM User ARNs for the 10 Clients"
  value       = module.iam_access.client_user_arns
}

output "clients_secret_arn" {
  description = "Secrets Manager ARN storing 10 Client credentials"
  value       = module.iam_access.clients_secret_arn
}
