###############################################################################
# Module: backtest_db
# Credentials of the isolated `nexusquant_backtest` database (inside the
# EXISTING RDS instance). Terraform only generates the password and stores it
# in Secrets Manager; the database and the login role are created once by
# scripts/create_backtest_db.py, which reads this secret (RDS is private, so
# Terraform never connects to it).
###############################################################################

resource "random_password" "backtest" {
  length  = 32
  special = false # alphanumeric only: safe in DSN URLs and shell env vars
}

resource "aws_secretsmanager_secret" "backtest_db" {
  name                    = "/${var.project_name}/${var.environment}/backtest/db"
  description             = "NexusQuant Backtest Engine - credentials of the isolated ${var.backtest_db_name} database"
  recovery_window_in_days = var.secret_recovery_window_days

  tags = {
    Name        = "${var.project_name}-secret-backtest-db-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_secretsmanager_secret_version" "backtest_db" {
  secret_id = aws_secretsmanager_secret.backtest_db.id

  secret_string = jsonencode({
    DB_USERNAME = var.backtest_db_username
    DB_PASSWORD = random_password.backtest.result
    DB_NAME     = var.backtest_db_name
  })
}
