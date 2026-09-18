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
  description = "AWS Region for latency-based routing"
  type        = string
}

variable "enable_route53_and_acm" {
  description = "Whether to create ACM certificate and Route 53 DNS records"
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Root domain name (e.g. staydriv.com)"
  type        = string
  default     = ""
}

variable "subdomain" {
  description = "Subdomain prefix (e.g. 'api' for api.staydriv.com). Leave empty for root."
  type        = string
  default     = ""
}

variable "subject_alternative_names" {
  description = "SANs for ACM certificate"
  type        = list(string)
  default     = []
}

variable "hosted_zone_id" {
  description = "Route 53 Hosted Zone ID"
  type        = string
  default     = ""
}

variable "alb_dns_name" {
  description = "ALB DNS Name for the Alias record"
  type        = string
  default     = ""
}

variable "alb_zone_id" {
  description = "ALB Canonical Hosted Zone ID"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
