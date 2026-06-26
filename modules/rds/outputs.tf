output "db_endpoint" { value = aws_db_instance.postgres.endpoint }
output "db_name" { value = aws_db_instance.postgres.db_name }
output "db_username" { value = aws_db_instance.postgres.username }
output "db_password" {
  value     = random_password.db_password.result
  sensitive = true
}
output "rds_sg_id" { value = aws_security_group.rds.id }
