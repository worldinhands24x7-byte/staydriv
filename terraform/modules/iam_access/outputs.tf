output "team_lead_user_name" {
  description = "IAM User Name for Team Lead"
  value       = var.create_iam_access && length(aws_iam_user.team_lead) > 0 ? aws_iam_user.team_lead[0].name : ""
}

output "team_lead_user_arn" {
  description = "IAM User ARN for Team Lead"
  value       = var.create_iam_access && length(aws_iam_user.team_lead) > 0 ? aws_iam_user.team_lead[0].arn : ""
}

output "team_lead_secret_arn" {
  description = "Secrets Manager ARN storing Team Lead credentials"
  value       = var.create_iam_access && length(aws_secretsmanager_secret.team_lead_credentials) > 0 ? aws_secretsmanager_secret.team_lead_credentials[0].arn : ""
}

output "client_user_names" {
  description = "List of IAM User Names for the 10 Clients"
  value       = var.create_iam_access ? aws_iam_user.clients[*].name : []
}

output "client_user_arns" {
  description = "List of IAM User ARNs for the 10 Clients"
  value       = var.create_iam_access ? aws_iam_user.clients[*].arn : []
}

output "clients_secret_arn" {
  description = "Secrets Manager ARN storing 10 Client credentials"
  value       = var.create_iam_access && length(aws_secretsmanager_secret.clients_credentials) > 0 ? aws_secretsmanager_secret.clients_credentials[0].arn : ""
}
