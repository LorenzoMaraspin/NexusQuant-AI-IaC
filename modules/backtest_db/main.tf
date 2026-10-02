###############################################################################
# Module: backtest_db
# Logical database `nexusquant_backtest` + dedicated login role inside the
# EXISTING RDS instance (reporting data fully separated from the live DB).
#
# The `postgresql` provider is configured in the root module and connects with
# the RDS master credentials. RDS sits in private subnets, so Terraform must
# reach it through an SSM port-forward (see root providers.tf).
###############################################################################

resource "random_password" "backtest" {
  length  = 32
  special = false # alphanumeric only: safe in DSN URLs and shell env vars
}

resource "postgresql_role" "backtest" {
  name             = var.backtest_db_username
  login            = true
  password         = random_password.backtest.result
  connection_limit = var.backtest_db_connection_limit
}

# On RDS the master user must be able to SET ROLE to the future owner,
# otherwise CREATE DATABASE ... OWNER fails ("must be member of role").
resource "postgresql_grant_role" "master_is_member" {
  role       = var.master_username
  grant_role = postgresql_role.backtest.name
}

resource "postgresql_database" "backtest" {
  name       = var.backtest_db_name
  owner      = postgresql_role.backtest.name
  encoding   = "UTF8"
  depends_on = [postgresql_grant_role.master_is_member]
}

# Only the owner (backtest role) and the master can connect.
resource "postgresql_grant" "revoke_public_connect" {
  database    = postgresql_database.backtest.name
  role        = "public"
  object_type = "database"
  privileges  = []
}

# Credentials for the ECS Task Execution Role (read access is granted in Fase 2).
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
    DB_USERNAME = postgresql_role.backtest.name
    DB_PASSWORD = random_password.backtest.result
    DB_NAME     = postgresql_database.backtest.name
  })
}
