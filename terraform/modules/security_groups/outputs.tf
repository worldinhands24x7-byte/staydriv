output "alb_security_group_id" {
  description = "Application Load Balancer Security Group ID"
  value       = aws_security_group.alb.id
}

output "ec2_security_group_id" {
  description = "EC2 Application Instances Security Group ID"
  value       = aws_security_group.ec2.id
}

output "rds_security_group_id" {
  description = "Amazon RDS Database Security Group ID"
  value       = aws_security_group.rds.id
}
