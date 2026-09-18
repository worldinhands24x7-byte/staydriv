variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "staydriv"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "bucket_purpose" {
  description = "Purpose of the bucket (e.g., assets, backups, logs)"
  type        = string
  default     = "assets"
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "enable_ia_transition" {
  description = "Enable transition to Standard-IA storage class after 90 days"
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow destroying the bucket even if it contains objects (useful for testing)"
  type        = bool
  default     = false
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
