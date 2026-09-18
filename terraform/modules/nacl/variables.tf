variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "staydriv"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "The CIDR of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "private_app_subnet_ids" {
  description = "List of private application subnet IDs"
  type        = list(string)
}

variable "private_db_subnet_ids" {
  description = "List of private database subnet IDs"
  type        = list(string)
}

variable "private_app_subnet_cidrs" {
  description = "List of private application subnet CIDRs"
  type        = list(string)
}

variable "app_port" {
  description = "Application listening port on EC2 instances"
  type        = number
  default     = 3000
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
