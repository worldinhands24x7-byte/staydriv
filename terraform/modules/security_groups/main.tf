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
# 1. APPLICATION LOAD BALANCER (ALB) SECURITY GROUP (PUBLIC)
# ==============================================================================
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-${var.environment}-alb-sg-"
  description = "Controls public inbound traffic to StayDriv ALB"
  vpc_id      = var.vpc_id

  # Inbound HTTP (80)
  ingress {
    description = "Allow public HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Inbound HTTPS (443)
  ingress {
    description = "Allow public HTTPS traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound to EC2 Application Instances on app_port
  egress {
    description = "Allow outbound to EC2 application instances"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-alb-sg"
      Tier = "Public"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# ==============================================================================
# 2. EC2 APPLICATION INSTANCES SECURITY GROUP (PRIVATE)
# ==============================================================================
resource "aws_security_group" "ec2" {
  name_prefix = "${var.project_name}-${var.environment}-ec2-sg-"
  description = "Controls traffic to StayDriv EC2 backend instances in private subnets"
  vpc_id      = var.vpc_id

  # Inbound Application Traffic strictly from ALB SG
  ingress {
    description     = "Allow inbound app traffic strictly from ALB"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Outbound to RDS MySQL (3306)
  egress {
    description = "Allow outbound to RDS MySQL in database subnets"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Outbound HTTPS for package updates, SSM Agent, AWS APIs, & external payment/maps APIs
  egress {
    description = "Allow outbound HTTPS for AWS services and APIs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound HTTP for OS repositories
  egress {
    description = "Allow outbound HTTP for software repository downloads"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-ec2-sg"
      Tier = "Private-App"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# ==============================================================================
# 3. AMAZON RDS MYSQL SECURITY GROUP (PRIVATE - STRICTLY ISOLATED)
# ==============================================================================
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-${var.environment}-rds-sg-"
  description = "Controls traffic to StayDriv MySQL RDS database"
  vpc_id      = var.vpc_id

  # Inbound MySQL (3306) strictly from EC2 Application SG
  ingress {
    description     = "Allow MySQL traffic strictly from EC2 application servers"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  # No general outbound internet connectivity permitted
  egress {
    description = "Allow outbound response to VPC only"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-rds-sg"
      Tier = "Private-DB"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}
