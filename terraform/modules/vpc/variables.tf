variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
  default     = "staydriv"
}

variable "environment" {
  description = "Deployment environment (e.g., prod, staging)"
  type        = string
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of 2 Availability Zones to use"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "List of 2 CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_app_subnet_cidrs" {
  description = "List of 2 CIDR blocks for private application subnets"
  type        = list(string)
}

variable "private_db_subnet_cidrs" {
  description = "List of 2 CIDR blocks for private database subnets"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Whether to use a single NAT Gateway (cost saver) or one per AZ (high availability)"
  type        = bool
  default     = false
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
