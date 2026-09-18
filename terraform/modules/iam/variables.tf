variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "staydriv"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "secrets_manager_arn" {
  description = "ARN of Secrets Manager secret to restrict access to (optional, defaults to wildcard if empty)"
  type        = string
  default     = ""
}

variable "s3_bucket_arn" {
  description = "ARN of S3 bucket to restrict access to (optional, defaults to wildcard if empty)"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
