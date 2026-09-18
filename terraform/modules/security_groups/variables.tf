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
  description = "VPC ID where security groups will be created"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "app_port" {
  description = "Application port (e.g., 3000 for StayDriv Node.js backend)"
  type        = number
  default     = 3000
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
