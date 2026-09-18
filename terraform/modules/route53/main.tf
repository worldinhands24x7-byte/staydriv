terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

# --- ACM SSL/TLS Certificate (Optional) ---
resource "aws_acm_certificate" "cert" {
  count             = var.enable_route53_and_acm ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"

  subject_alternative_names = var.subject_alternative_names

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-acm-cert"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# --- Route 53 DNS Validation Record for ACM ---
resource "aws_route53_record" "cert_validation" {
  for_each = var.enable_route53_and_acm && var.hosted_zone_id != "" ? {
    for dvo in aws_acm_certificate.cert[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.hosted_zone_id
}

# --- ACM Certificate Validation Completion ---
resource "aws_acm_certificate_validation" "cert" {
  count                   = var.enable_route53_and_acm && var.hosted_zone_id != "" ? 1 : 0
  certificate_arn         = aws_acm_certificate.cert[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# --- Route 53 Alias Record pointing to Regional ALB (with Latency Routing) ---
resource "aws_route53_record" "alb_alias" {
  count   = var.enable_route53_and_acm && var.hosted_zone_id != "" ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = var.subdomain != "" ? "${var.subdomain}.${var.domain_name}" : var.domain_name
  type    = "A"

  # Latency Routing policy automatically routes users to closest AWS region
  latency_routing_policy {
    region = var.aws_region
  }

  set_identifier = "${var.project_name}-${var.aws_region}"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}
