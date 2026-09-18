terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
  }
}

# --- DB Subnet Group (Private Database Subnets Across 2 AZs) ---
resource "aws_db_subnet_group" "main" {
  name_prefix = "${var.project_name}-${var.environment}-db-subnet-group-"
  subnet_ids  = var.private_db_subnet_ids
  description = "StayDriv private database subnet group"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-db-subnet-group"
      Tier = "Private-DB"
    }
  )
}

# --- Custom Parameter Group for UTF8mb4 & Performance ---
resource "aws_db_parameter_group" "mysql" {
  name_prefix = "${var.project_name}-${var.environment}-mysql-pg-"
  family      = "mysql8.0"
  description = "Custom parameter group for StayDriv MySQL 8.0"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  parameter {
    name  = "max_connections"
    value = "500"
  }

  tags = var.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# --- Generate Strong Random Password for Master User ---
resource "random_password" "master_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# --- Amazon RDS MySQL Instance (Private & Encrypted) ---
resource "aws_db_instance" "main" {
  identifier_prefix     = "${var.project_name}-${var.environment}-mysql-"
  engine                = "mysql"
  engine_version        = var.mysql_version
  instance_class        = var.db_instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  multi_az              = var.multi_az
  publicly_accessible   = false

  db_name  = var.database_name
  username = var.db_username
  password = random_password.master_password.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  parameter_group_name   = aws_db_parameter_group.mysql.name
  vpc_security_group_ids = [var.rds_security_group_id]

  backup_retention_period   = var.backup_retention_period
  backup_window             = "03:00-04:00"
  maintenance_window        = "Mon:04:30-Mon:05:30"
  copy_tags_to_snapshot     = true
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = "${var.project_name}-${var.environment}-mysql-final-snapshot"

  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-rds-mysql"
      Tier = "Private-DB"
    }
  )

  lifecycle {
    ignore_changes = [password]
  }
}

# --- AWS Secrets Manager: Secure Storage for Database Credentials ---
resource "aws_secretsmanager_secret" "db_credentials" {
  name_prefix = "${var.project_name}-${var.environment}-db-credentials-"
  description = "StayDriv Master MySQL database credentials"

  recovery_window_in_days = 0 # Immediate deletion on destroy for testing/re-deploy

  tags = var.common_tags
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    engine   = "mysql"
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    database = var.database_name
    username = var.db_username
    password = random_password.master_password.result
    url      = "mysql://${var.db_username}:${urlencode(random_password.master_password.result)}@${aws_db_instance.main.address}:${aws_db_instance.main.port}/${var.database_name}"
  })
}
