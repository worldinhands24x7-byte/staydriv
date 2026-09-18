output "app_log_group_name" {
  description = "CloudWatch Application Log Group Name"
  value       = aws_cloudwatch_log_group.app.name
}

output "app_log_group_arn" {
  description = "CloudWatch Application Log Group ARN"
  value       = aws_cloudwatch_log_group.app.arn
}

output "dashboard_name" {
  description = "CloudWatch Dashboard Name"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}
