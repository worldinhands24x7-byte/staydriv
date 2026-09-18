# --- Global Variables ---
variable "project_name" {
  description = "Project name prefix for all StayDriv resources"
  type        = string
  default     = "staydriv"
}

variable "environment" {
  description = "Deployment environment (e.g. prod, staging)"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS deployment region"
  type        = string
  default     = "us-east-1"
}

# --- Network & VPC Variables ---
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.10.0.0/16"
}

variable "availability_zones" {
  description = "List of 2 Availability Zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "List of 2 public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.10.1.0/24", "10.10.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "List of 2 private application subnet CIDR blocks"
  type        = list(string)
  default     = ["10.10.11.0/24", "10.10.12.0/24"]
}

variable "private_db_subnet_cidrs" {
  description = "List of 2 private database subnet CIDR blocks"
  type        = list(string)
  default     = ["10.10.21.0/24", "10.10.22.0/24"]
}

variable "single_nat_gateway" {
  description = "Whether to use 1 NAT Gateway for cost-efficiency or 1 per AZ for high availability"
  type        = bool
  default     = false
}

# --- Compute & Auto Scaling Variables ---
variable "instance_type" {
  description = "EC2 instance type for application backend"
  type        = string
  default     = "t3.small"
}

variable "desired_capacity" {
  description = "Desired number of EC2 instances in the Auto Scaling Group"
  type        = number
  default     = 2
}

variable "minimum_capacity" {
  description = "Minimum number of EC2 instances in the Auto Scaling Group"
  type        = number
  default     = 2
}

variable "maximum_capacity" {
  description = "Maximum number of EC2 instances in the Auto Scaling Group"
  type        = number
  default     = 4
}

variable "create_iam_access" {
  description = "Whether to create IAM user accounts for Team Lead and 10 Clients"
  type        = bool
  default     = true
}

variable "app_port" {
  description = "Port the application listens on"
  type        = number
  default     = 3000
}

# --- Database Variables ---
variable "db_instance_class" {
  description = "RDS DB instance class"
  type        = string
  default     = "db.t4g.small"
}

variable "database_name" {
  description = "Database name"
  type        = string
  default     = "staydriv"
}

variable "db_username" {
  description = "Master database username"
  type        = string
  default     = "staydrivadmin"
}

variable "multi_az" {
  description = "Enable Multi-AZ deployment for Amazon RDS"
  type        = bool
  default     = true
}

# --- Route 53 & ACM Variables ---
variable "enable_route53_and_acm" {
  description = "Whether to provision ACM certificate and Route 53 DNS records"
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Root domain name (e.g. staydriv.com)"
  type        = string
  default     = ""
}

variable "subdomain" {
  description = "Subdomain (e.g. api)"
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route 53 Hosted Zone ID"
  type        = string
  default     = ""
}
