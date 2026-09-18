# StayDriv Production - US East (N. Virginia) Environment Configuration

project_name = "staydriv"
environment  = "prod"
aws_region   = "us-east-1"

# Network Configuration (VPC 10.10.0.0/16)
vpc_cidr                 = "10.10.0.0/16"
availability_zones       = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs      = ["10.10.1.0/24", "10.10.2.0/24"]
private_app_subnet_cidrs = ["10.10.11.0/24", "10.10.12.0/24"]
private_db_subnet_cidrs  = ["10.10.21.0/24", "10.10.22.0/24"]
single_nat_gateway       = false # true for 1 NAT GW (cost saving); false for 2 NAT GWs (full HA)

# Compute & Auto Scaling Group Configuration
instance_type    = "t3.small"
desired_capacity = 2
minimum_capacity = 2
maximum_capacity = 4
app_port         = 3000

# IAM Access Management (1 Team Lead + 10 Clients)
create_iam_access = true

# Database Configuration
db_instance_class = "db.t4g.small"
database_name     = "staydriv"
db_username       = "staydrivadmin"
multi_az          = true

# Domain & ACM Configuration (Set to true when domain is configured in Route 53)
enable_route53_and_acm = false
domain_name            = "staydriv.com"
subdomain              = "us-api"
hosted_zone_id         = ""
