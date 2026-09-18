output "db_instance_id" {
  description = "The RDS instance ID"
  value       = aws_db_instance.main.id
}

output "db_instance_address" {
  description = "The address of the RDS instance"
  value       = aws_db_instance.main.address
}

output "db_instance_endpoint" {
  description = "The connection endpoint (address:port) of the RDS instance"
  value       = aws_db_instance.main.endpoint
}

output "db_instance_port" {
  description = "The port the database is listening on"
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "The default database name"
  value       = aws_db_instance.main.db_name
}

output "db_secrets_manager_arn" {
  description = "ARN of Secrets Manager secret containing database credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "db_secrets_manager_name" {
  description = "Name of Secrets Manager secret containing database credentials"
  value       = aws_secretsmanager_secret.db_credentials.name
}
