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

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB placement"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security Group ID for the ALB"
  type        = string
}

variable "app_port" {
  description = "Port the application backend listens on"
  type        = number
  default     = 3000
}

variable "health_check_path" {
  description = "Health check HTTP path"
  type        = string
  default     = "/"
}

variable "certificate_arn" {
  description = "ACM Certificate ARN for HTTPS listener (optional)"
  type        = string
  default     = ""
}

variable "enable_waf" {
  description = "Whether to provision and associate AWS WAFv2"
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Enable ALB deletion protection"
  type        = bool
  default     = false
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
