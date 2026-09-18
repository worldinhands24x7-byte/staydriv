variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "staydriv"
}

variable "create_iam_access" {
  description = "Whether to create IAM users and groups (enable in primary region to avoid duplicate global IAM resources)"
  type        = bool
  default     = true
}

variable "s3_bucket_arn" {
  description = "ARN of S3 bucket for client read access policy"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
