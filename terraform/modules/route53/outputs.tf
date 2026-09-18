output "certificate_arn" {
  description = "ACM Certificate ARN (if created and validated)"
  value       = var.enable_route53_and_acm && length(aws_acm_certificate.cert) > 0 ? aws_acm_certificate.cert[0].arn : ""
}

output "dns_record_fqdn" {
  description = "FQDN of the Route 53 ALB alias record"
  value       = var.enable_route53_and_acm && length(aws_route53_record.alb_alias) > 0 ? aws_route53_record.alb_alias[0].fqdn : ""
}
