terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

# ==============================================================================
# 1. PUBLIC SUBNET NETWORK ACL
# ==============================================================================
resource "aws_network_acl" "public" {
  vpc_id     = var.vpc_id
  subnet_ids = var.public_subnet_ids

  # Inbound HTTP (80)
  ingress {
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
    protocol   = "tcp"
  }

  # Inbound HTTPS (443)
  ingress {
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
    protocol   = "tcp"
  }

  # Inbound Ephemeral Ports (for return traffic from internet/clients)
  ingress {
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
    protocol   = "tcp"
  }

  # Outbound All Traffic (for public internet routing & forwarding to private app tier)
  egress {
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
    protocol   = "-1"
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-public-nacl"
      Tier = "Public"
    }
  )
}

# ==============================================================================
# 2. PRIVATE APPLICATION SUBNET NETWORK ACL
# ==============================================================================
resource "aws_network_acl" "private_app" {
  vpc_id     = var.vpc_id
  subnet_ids = var.private_app_subnet_ids

  # Inbound Application Traffic (Port 3000) from VPC (ALB)
  ingress {
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = var.app_port
    to_port    = var.app_port
    protocol   = "tcp"
  }

  # Inbound Ephemeral Ports (Responses from outbound NAT Gateway & DB)
  ingress {
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
    protocol   = "tcp"
  }

  # Outbound MySQL Traffic (Port 3306) to Database Subnets
  egress {
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 3306
    to_port    = 3306
    protocol   = "tcp"
  }

  # Outbound HTTPS (443) for package downloads, AWS APIs, external webhooks (Razorpay/Google Maps)
  egress {
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
    protocol   = "tcp"
  }

  # Outbound HTTP (80) for repository mirrors & cert validation
  egress {
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
    protocol   = "tcp"
  }

  # Outbound Ephemeral Ports (Response traffic back to ALB in Public Subnets)
  egress {
    rule_no    = 130
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 1024
    to_port    = 65535
    protocol   = "tcp"
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-private-app-nacl"
      Tier = "Private-App"
    }
  )
}

# ==============================================================================
# 3. PRIVATE DATABASE SUBNET NETWORK ACL (ISOLATED)
# ==============================================================================
resource "aws_network_acl" "private_db" {
  vpc_id     = var.vpc_id
  subnet_ids = var.private_db_subnet_ids

  # Inbound MySQL Traffic (Port 3306) strictly from Private App Subnet CIDRs
  dynamic "ingress" {
    for_each = var.private_app_subnet_cidrs
    content {
      rule_no    = 100 + ingress.key
      action     = "allow"
      cidr_block = ingress.value
      from_port  = 3306
      to_port    = 3306
      protocol   = "tcp"
    }
  }

  # Outbound Ephemeral Traffic (1024-65535) strictly to Private App Subnet CIDRs
  dynamic "egress" {
    for_each = var.private_app_subnet_cidrs
    content {
      rule_no    = 100 + egress.key
      action     = "allow"
      cidr_block = egress.value
      from_port  = 1024
      to_port    = 65535
      protocol   = "tcp"
    }
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-private-db-nacl"
      Tier = "Private-DB"
    }
  )
}
