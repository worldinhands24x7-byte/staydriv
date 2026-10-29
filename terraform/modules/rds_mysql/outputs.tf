output "db_instance_id" {
  description = "The RDS instance ID"
  value       = try(aws_db_instance.main[0].id, "")
}

output "db_instance_address" {
  description = "The address of the RDS instance"
  value       = try(aws_db_instance.main[0].address, "")
}

output "db_instance_endpoint" {
  description = "The connection endpoint (address:port) of the RDS instance"
  value       = try(aws_db_instance.main[0].endpoint, "")
}

output "db_instance_port" {
  description = "The port the database is listening on"
  value       = try(aws_db_instance.main[0].port, 3306)
}

output "db_name" {
  description = "The default database name"
  value       = try(aws_db_instance.main[0].db_name, "")
}

output "db_secrets_manager_arn" {
  description = "ARN of Secrets Manager secret containing database credentials"
  value       = try(aws_secretsmanager_secret.db_credentials[0].arn, "")
}

output "db_secrets_manager_name" {
  description = "Name of Secrets Manager secret containing database credentials"
  value       = try(aws_secretsmanager_secret.db_credentials[0].name, "")
}

