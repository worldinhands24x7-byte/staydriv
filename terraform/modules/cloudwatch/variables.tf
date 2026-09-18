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

variable "asg_name" {
  description = "Auto Scaling Group Name"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN Suffix for CloudWatch metrics"
  type        = string
}

variable "db_instance_id" {
  description = "RDS DB Instance Identifier"
  type        = string
}

variable "log_retention_days" {
  description = "Log retention in days"
  type        = number
  default     = 30
}

variable "sns_alert_topic_arn" {
  description = "Optional SNS topic ARN for CloudWatch alarm notifications"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
