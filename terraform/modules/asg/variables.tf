variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "staydriv"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "custom_ami_id" {
  description = "Custom AMI ID (optional, defaults to dynamic Ubuntu 24.04 LTS)"
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 20
}

variable "instance_profile_arn" {
  description = "IAM Instance Profile ARN"
  type        = string
}

variable "ec2_security_group_id" {
  description = "Security Group ID for EC2 instances"
  type        = string
}

variable "private_app_subnet_ids" {
  description = "List of private application subnet IDs"
  type        = list(string)
}

variable "target_group_arn" {
  description = "Target Group ARN to register instances with"
  type        = string
}

variable "desired_capacity" {
  description = "Desired number of EC2 instances"
  type        = number
  default     = 2
}

variable "minimum_capacity" {
  description = "Minimum number of EC2 instances"
  type        = number
  default     = 2
}

variable "maximum_capacity" {
  description = "Maximum number of EC2 instances"
  type        = number
  default     = 6
}

variable "app_port" {
  description = "Application port"
  type        = number
  default     = 3000
}

variable "db_secret_arn" {
  description = "AWS Secrets Manager Secret ARN for DB credentials (optional)"
  type        = string
  default     = ""
}

variable "db_endpoint" {
  description = "Database endpoint address (optional)"
  type        = string
  default     = ""
}

variable "s3_bucket_name" {
  description = "S3 bucket name (optional)"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
