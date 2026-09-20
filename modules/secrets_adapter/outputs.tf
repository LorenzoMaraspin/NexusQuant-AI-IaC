output "secret_arn" {
  description = "ARN of the Secrets Manager secret for the MT5 adapter."
  value       = aws_secretsmanager_secret.mt5_adapter.arn
}

output "secret_name" {
  description = "Name of the Secrets Manager secret."
  value       = aws_secretsmanager_secret.mt5_adapter.name
}

output "ssm_prefix" {
  description = "SSM Parameter Store prefix used for all config parameters."
  value       = local.ssm_prefix
}
