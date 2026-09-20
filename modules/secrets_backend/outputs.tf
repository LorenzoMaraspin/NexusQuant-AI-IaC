output "secret_arn" {
  description = "ARN of the Secrets Manager secret for the backend."
  value       = aws_secretsmanager_secret.backend.arn
}

output "secret_name" {
  description = "Name of the Secrets Manager secret."
  value       = aws_secretsmanager_secret.backend.name
}

output "ssm_prefix" {
  description = "SSM Parameter Store prefix used for backend config."
  value       = local.ssm_prefix
}

output "ssm_param_arns" {
  description = "Map of parameter name to ARN for all backend SSM parameters created."
  value       = { for k, p in aws_ssm_parameter.backend_config : k => p.arn }
}
