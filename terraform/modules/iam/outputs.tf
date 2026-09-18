output "instance_profile_name" {
  description = "IAM instance profile name"
  value       = aws_iam_instance_profile.ec2_profile.name
}

output "instance_profile_arn" {
  description = "IAM instance profile ARN"
  value       = aws_iam_instance_profile.ec2_profile.arn
}

output "role_name" {
  description = "IAM role name"
  value       = aws_iam_role.ec2_role.name
}

output "role_arn" {
  description = "IAM role ARN"
  value       = aws_iam_role.ec2_role.arn
}
