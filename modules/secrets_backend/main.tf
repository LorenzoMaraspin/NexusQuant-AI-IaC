###############################################################################
# Module: secrets_backend
# Secrets Manager (sensitive) + SSM Parameter Store (config) for the
# NexusQuant AI backend.
###############################################################################

locals {
  ssm_prefix = "/${var.project_name}/${var.environment}/backend"
}

resource "aws_secretsmanager_secret" "backend" {
  name                    = "/${var.project_name}/${var.environment}/backend/secrets"
  description             = "NexusQuant AI backend sensitive credentials"
  recovery_window_in_days = var.secret_recovery_window_days

  tags = {
    Name        = "${var.project_name}-secret-backend-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_secretsmanager_secret_version" "backend" {
  secret_id = aws_secretsmanager_secret.backend.id

  secret_string = jsonencode({
    NEWS_CALENDAR_API_KEY = var.news_calendar_api_key
  })
}

resource "aws_ssm_parameter" "backend_config" {
  for_each = var.backend_ssm_params

  name  = "${local.ssm_prefix}/${each.key}"
  type  = "String"
  value = each.value

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
