output "endpoint" {
  description = "RDS instance endpoint (host only, without port)."
  value       = aws_db_instance.main.address
}

output "port" {
  description = "RDS instance port."
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Name of the created database."
  value       = aws_db_instance.main.db_name
}

output "instance_id" {
  description = "RDS instance identifier."
  value       = aws_db_instance.main.identifier
}
