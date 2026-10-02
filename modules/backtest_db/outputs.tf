output "secret_arn" {
  description = "ARN of the Secrets Manager secret with the backtest DB credentials (keys: DB_USERNAME, DB_PASSWORD, DB_NAME)."
  value       = aws_secretsmanager_secret.backtest_db.arn
}

output "db_name" {
  description = "Name of the backtest logical database."
  value       = var.backtest_db_name
}

output "db_username" {
  description = "Dedicated backtest login role."
  value       = var.backtest_db_username
}
