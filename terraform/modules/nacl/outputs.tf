output "public_nacl_id" {
  description = "Public Subnet Network ACL ID"
  value       = aws_network_acl.public.id
}

output "private_app_nacl_id" {
  description = "Private App Subnet Network ACL ID"
  value       = aws_network_acl.private_app.id
}

output "private_db_nacl_id" {
  description = "Private Database Subnet Network ACL ID"
  value       = aws_network_acl.private_db.id
}
