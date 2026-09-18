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
# 1. TEAM LEAD IAM GROUP & USER
# ==============================================================================
resource "aws_iam_group" "team_leads" {
  count = var.create_iam_access ? 1 : 0
  name  = "${var.project_name}-team-leads"
}

# Policy for Team Lead: Full Operational & Monitoring Access to StayDriv Stack
resource "aws_iam_policy" "team_lead_policy" {
  count       = var.create_iam_access ? 1 : 0
  name        = "${var.project_name}-team-lead-policy"
  description = "Operational management access for StayDriv Team Lead"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StayDrivComputeAndNetworkReadWrite"
        Effect = "Allow"
        Action = [
          "ec2:*",
          "elasticloadbalancing:*",
          "autoscaling:*",
          "rds:*",
          "s3:*",
          "cloudwatch:*",
          "logs:*",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "ssm:StartSession",
          "ssm:DescribeSessions",
          "ssm:GetConnectionStatus"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_group_policy_attachment" "team_lead" {
  count      = var.create_iam_access ? 1 : 0
  group      = aws_iam_group.team_leads[0].name
  policy_arn = aws_iam_policy.team_lead_policy[0].arn
}

# Team Lead User
resource "aws_iam_user" "team_lead" {
  count         = var.create_iam_access ? 1 : 0
  name          = "${var.project_name}-teamlead"
  force_destroy = true

  tags = merge(
    var.common_tags,
    {
      Role = "TeamLead"
    }
  )
}

resource "aws_iam_user_group_membership" "team_lead" {
  count = var.create_iam_access ? 1 : 0
  user  = aws_iam_user.team_lead[0].name
  groups = [
    aws_iam_group.team_leads[0].name
  ]
}

# Team Lead Access Key
resource "aws_iam_access_key" "team_lead" {
  count = var.create_iam_access ? 1 : 0
  user  = aws_iam_user.team_lead[0].name
}

# Store Team Lead Access Key in AWS Secrets Manager
resource "aws_secretsmanager_secret" "team_lead_credentials" {
  count                   = var.create_iam_access ? 1 : 0
  name_prefix             = "${var.project_name}-credentials-teamlead-"
  description             = "IAM Access Keys for StayDriv Team Lead"
  recovery_window_in_days = 0

  tags = var.common_tags
}

resource "aws_secretsmanager_secret_version" "team_lead_credentials" {
  count     = var.create_iam_access ? 1 : 0
  secret_id = aws_secretsmanager_secret.team_lead_credentials[0].id
  secret_string = jsonencode({
    user              = aws_iam_user.team_lead[0].name
    access_key_id     = aws_iam_access_key.team_lead[0].id
    secret_access_key = aws_iam_access_key.team_lead[0].secret
  })
}

# ==============================================================================
# 2. 10 CLIENTS IAM GROUP & USERS
# ==============================================================================
resource "aws_iam_group" "clients" {
  count = var.create_iam_access ? 1 : 0
  name  = "${var.project_name}-clients"
}

# Scoped Policy for Clients: Read-only access to S3 application assets and CloudWatch status
resource "aws_iam_policy" "client_policy" {
  count       = var.create_iam_access ? 1 : 0
  name        = "${var.project_name}-client-policy"
  description = "Scoped read access for StayDriv client accounts"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ClientS3ReadAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = var.s3_bucket_arn != "" ? [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ] : ["*"]
      },
      {
        Sid    = "ClientCloudWatchReadMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_group_policy_attachment" "clients" {
  count      = var.create_iam_access ? 1 : 0
  group      = aws_iam_group.clients[0].name
  policy_arn = aws_iam_policy.client_policy[0].arn
}

# 10 Client Users
resource "aws_iam_user" "clients" {
  count         = var.create_iam_access ? 10 : 0
  name          = format("${var.project_name}-client-%02d", count.index + 1)
  force_destroy = true

  tags = merge(
    var.common_tags,
    {
      Role   = "Client"
      Client = format("client-%02d", count.index + 1)
    }
  )
}

resource "aws_iam_user_group_membership" "clients" {
  count = var.create_iam_access ? 10 : 0
  user  = aws_iam_user.clients[count.index].name
  groups = [
    aws_iam_group.clients[0].name
  ]
}

# 10 Client Access Keys
resource "aws_iam_access_key" "clients" {
  count = var.create_iam_access ? 10 : 0
  user  = aws_iam_user.clients[count.index].name
}

# Store All Client Credentials securely in Secrets Manager
resource "aws_secretsmanager_secret" "clients_credentials" {
  count                   = var.create_iam_access ? 1 : 0
  name_prefix             = "${var.project_name}-credentials-clients-"
  description             = "IAM Access Keys for 10 StayDriv Client Accounts"
  recovery_window_in_days = 0

  tags = var.common_tags
}

resource "aws_secretsmanager_secret_version" "clients_credentials" {
  count     = var.create_iam_access ? 1 : 0
  secret_id = aws_secretsmanager_secret.clients_credentials[0].id
  secret_string = jsonencode({
    clients = [
      for i in range(10) : {
        user              = aws_iam_user.clients[i].name
        access_key_id     = aws_iam_access_key.clients[i].id
        secret_access_key = aws_iam_access_key.clients[i].secret
      }
    ]
  })
}
