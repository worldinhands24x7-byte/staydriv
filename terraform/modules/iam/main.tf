terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

# --- IAM Role for EC2 Instances ---
resource "aws_iam_role" "ec2_role" {
  name_prefix = "${var.project_name}-${var.environment}-ec2-role-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-ec2-iam-role"
    }
  )
}

# --- Attach AWS Managed Policy: SSM Managed Instance Core ---
# Enables AWS Systems Manager Session Manager (Zero open SSH port 22 required)
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# --- Attach AWS Managed Policy: CloudWatch Agent Server Policy ---
# Allows EC2 instances to stream application logs and custom system metrics
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# --- Custom Policy: Read Secrets Manager (RDS & App Credentials) ---
resource "aws_iam_policy" "secrets_manager_access" {
  name_prefix = "${var.project_name}-${var.environment}-secrets-policy-"
  description = "Allows EC2 instances to read secrets from AWS Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.secrets_manager_arn != "" ? [var.secrets_manager_arn] : ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "secrets_manager" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.secrets_manager_access.arn
}

# --- Custom Policy: S3 Bucket Access (Read / Write for App Assets) ---
resource "aws_iam_policy" "s3_access" {
  name_prefix = "${var.project_name}-${var.environment}-s3-policy-"
  description = "Allows EC2 instances to read and write to StayDriv S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = var.s3_bucket_arn != "" ? [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ] : ["*"]
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "s3" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_access.arn
}

# --- IAM Instance Profile ---
resource "aws_iam_instance_profile" "ec2_profile" {
  name_prefix = "${var.project_name}-${var.environment}-ec2-profile-"
  role        = aws_iam_role.ec2_role.name

  tags = var.common_tags
}
