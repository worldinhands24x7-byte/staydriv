# StayDriv Production - Asia Pacific (Hyderabad) Environment Configuration

project_name = "staydriv"
environment  = "prod"
aws_region   = "ap-south-2"

# Network Configuration (VPC 10.20.0.0/16)
vpc_cidr                 = "10.20.0.0/16"
availability_zones       = ["ap-south-2a", "ap-south-2b"]
public_subnet_cidrs      = ["10.20.1.0/24", "10.20.2.0/24"]
private_app_subnet_cidrs = ["10.20.11.0/24", "10.20.12.0/24"]
private_db_subnet_cidrs  = ["10.20.21.0/24", "10.20.22.0/24"]
single_nat_gateway       = false # true for 1 NAT GW (cost saving); false for 2 NAT GWs (full HA)

# Compute & Auto Scaling Group Configuration
instance_type    = "t3.small"
desired_capacity = 2
minimum_capacity = 2
maximum_capacity = 4
app_port         = 3000

# IAM Access Management (Global IAM users provisioned via primary region us-east-1)
create_iam_access = false

# Database Configuration
db_instance_class = "db.t4g.small"
database_name     = "staydriv"
db_username       = "staydrivadmin"
multi_az          = true

# Domain & ACM Configuration (Set to true when domain is configured in Route 53)
enable_route53_and_acm = false
domain_name            = "staydriv.com"
subdomain              = "hyd-api"
hosted_zone_id         = ""
