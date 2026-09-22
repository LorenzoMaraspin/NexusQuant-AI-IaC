###############################################################################
# Module: secrets_adapter
# Secrets Manager (sensitive) + SSM Parameter Store (config) for MT5 Adapter
###############################################################################

resource "aws_secretsmanager_secret" "mt5_adapter" {
  name                    = "/${var.project_name}/${var.environment}/mt5-adapter/secrets"
  description             = "NexusQuant MT5 Adapter sensitive credentials"
  recovery_window_in_days = var.secret_recovery_window_days

  tags = {
    Name        = "${var.project_name}-secret-mt5-adapter-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_secretsmanager_secret_version" "mt5_adapter" {
  secret_id = aws_secretsmanager_secret.mt5_adapter.id

  secret_string = jsonencode({
    ADAPTER_API_KEY = var.adapter_api_key
    MT5_PASSWORD    = var.mt5_password
    POSTGRES_URL    = "postgresql+psycopg://${var.db_username}:${var.db_password}@${var.rds_endpoint}:5432/${var.db_name}"
    DB_USERNAME     = var.db_username
    DB_PASSWORD     = var.db_password
    GITHUB_TOKEN    = var.github_token
  })
}

# --- SSM Non-sensitive config ---

locals {
  ssm_prefix = "/${var.project_name}/${var.environment}"
  ssm_params = {
    MT5_ACCOUNT_NUMBER        = tostring(var.mt5_account_number)
    MT5_SERVER                = var.mt5_server
    MT5_TERMINAL_PATH         = var.mt5_terminal_path
    MT5_DEFAULT_DEVIATION     = tostring(var.mt5_default_deviation)
    ADAPTER_HOST              = "0.0.0.0"
    ADAPTER_PORT              = "8100"
    MT5_CONNECT_RETRY_SECONDS = "5"
    MT5_CONNECT_MAX_RETRIES   = "10"
    LOG_LEVEL_CONSOLE         = var.log_level_console
    LOG_LEVEL_FILE            = var.log_level_file
    ADAPTER_DB_PATH           = "data/adapter_trade_log.db"
    LOG_FILE_PATH             = "logs/mt5_adapter.log"
  }
}

resource "aws_ssm_parameter" "config" {
  for_each = local.ssm_params

  name  = "${local.ssm_prefix}/${each.key}"
  type  = "String"
  value = each.value

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
