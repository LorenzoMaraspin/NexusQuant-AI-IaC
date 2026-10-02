###############################################################################
# Root Terraform Outputs — NexusQuant AI Infrastructure
###############################################################################

# =============================================================================
# Networking
# =============================================================================

output "vpc_id" {
  description = "ID of the created VPC."
  value       = module.networking.vpc_id
}

output "subnet_public_id" {
  description = "Public subnet ID (NAT Gateway / EC2 RDP)."
  value       = module.networking.subnet_public_id
}

output "subnet_private_linux_id" {
  description = "Private Linux subnet ID where the ECS Fargate backend runs."
  value       = module.networking.subnet_private_linux_id
}

output "subnet_private_windows_id" {
  description = "Private Windows subnet ID."
  value       = module.networking.subnet_private_windows_id
}

# =============================================================================
# RDS PostgreSQL
# =============================================================================

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint hostname."
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "RDS PostgreSQL port."
  value       = module.rds.port
}

output "rds_db_name" {
  description = "RDS PostgreSQL database name."
  value       = module.rds.db_name
}

# =============================================================================
# MT5 Connector (EC2 Windows & Secrets)
# =============================================================================

output "ec2_windows_instance_id" {
  description = "EC2 Windows instance ID."
  value       = module.ec2_windows.instance_id
}

output "ec2_windows_private_ip" {
  description = "Private IP of the Windows EC2 instance (internal REST endpoint host)."
  value       = module.ec2_windows.private_ip
}

output "ec2_windows_public_ip" {
  description = "Public IP of the Windows EC2 instance (enter into Remote Desktop Connection / mstsc)."
  value       = module.ec2_windows.public_ip
}

output "ec2_windows_key_pair_name" {
  description = "Name of the EC2 key pair used by the Windows instance."
  value       = module.ec2_windows.key_pair_name
}

output "ec2_windows_private_key_pem" {
  description = "Private key PEM material for the auto-created Windows EC2 key pair."
  value       = module.ec2_windows.private_key_pem
  sensitive   = true
}

output "ec2_windows_private_key_secret_arn" {
  description = "ARN of the Secrets Manager secret storing the EC2 Windows private key PEM."
  value       = module.ec2_windows.private_key_secret_arn
}

output "ec2_windows_private_key_secret_name" {
  description = "Name of the Secrets Manager secret storing the EC2 Windows private key PEM."
  value       = module.ec2_windows.private_key_secret_name
}

output "ec2_windows_admin_password" {
  description = "Current local Administrator password for the Windows EC2 instance, decrypted by Terraform from the instance's EC2-generated password data."
  value       = module.ec2_windows.windows_admin_password
  sensitive   = true
}

output "ec2_windows_admin_password_secret_arn" {
  description = "ARN of the Secrets Manager secret storing the current EC2 Windows Administrator password."
  value       = module.ec2_windows.windows_admin_password_secret_arn
}

output "ec2_windows_admin_password_secret_name" {
  description = "Name of the Secrets Manager secret storing the current EC2 Windows Administrator password."
  value       = module.ec2_windows.windows_admin_password_secret_name
}

output "secrets_adapter_arn" {
  description = "ARN of the Secrets Manager secret for MT5 Adapter credentials."
  value       = module.secrets_adapter.secret_arn
}

output "secrets_adapter_ssm_prefix" {
  description = "SSM Parameter Store prefix for MT5 Adapter configuration."
  value       = module.secrets_adapter.ssm_prefix
}

output "ec2_windows_log_group_name" {
  description = "CloudWatch log group name for the EC2 MT5 adapter."
  value       = module.ec2_windows.cloudwatch_log_group_name
}

output "ec2_windows_log_group_arn" {
  description = "CloudWatch log group ARN for the EC2 MT5 adapter."
  value       = module.ec2_windows.cloudwatch_log_group_arn
}

# =============================================================================
# Backend (ECR, ECS Fargate & Secrets)
# =============================================================================

output "ecr_repository_url" {
  description = "ECR repository URL for the backend Docker image (docker push target)."
  value       = module.ecr.repository_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster running the backend."
  value       = var.enable_ecs_backend ? module.ecs_backend[0].cluster_name : null
}

output "ecs_service_name" {
  description = "Name of the ECS service for the backend trading loop."
  value       = var.enable_ecs_backend ? module.ecs_backend[0].service_name : null
}

output "backend_secrets_manager_arn" {
  description = "ARN of the backend Secrets Manager secret."
  value       = module.secrets_backend.secret_arn
}

output "backend_ssm_prefix" {
  description = "SSM prefix for backend-specific parameters."
  value       = module.secrets_backend.ssm_prefix
}

output "mt5_adapter_base_url" {
  description = "Calculated MT5 Adapter REST API base URL wired to the backend."
  value       = "http://${module.ec2_windows.private_ip}:8100"
}

# --- Backtest Engine ---

output "backtest_subnet_id" {
  description = "Isolated private subnet for the Backtest Engine Fargate tasks."
  value       = module.networking.subnet_private_backtest_id
}

output "backtest_security_group_id" {
  description = "Security Group of the Backtest Engine tasks."
  value       = module.networking.sg_backtest_id
}

output "s3_gateway_endpoint_id" {
  description = "S3 Gateway VPC Endpoint ID."
  value       = module.networking.vpc_endpoint_s3_id
}

output "backtest_db_secret_arn" {
  description = "Secrets Manager ARN with the backtest DB credentials."
  value       = module.backtest_db.secret_arn
}

output "backtest_cluster_name" {
  description = "ECS cluster running the one-off backtest tasks (null until enable_backtest_engine = true)."
  value       = var.enable_backtest_engine ? module.backtest_ecs[0].cluster_name : null
}

output "backtest_task_definition_arn" {
  description = "Backtest task definition ARN without revision (null until enable_backtest_engine = true)."
  value       = var.enable_backtest_engine ? module.backtest_ecs[0].task_definition_family_arn : null
}

output "backtest_task_role_arn" {
  value = var.enable_backtest_engine ? module.backtest_ecs[0].task_role_arn : null
}

output "backtest_execution_role_arn" {
  value = var.enable_backtest_engine ? module.backtest_ecs[0].execution_role_arn : null
}

output "backtest_state_machine_arn" {
  description = "Step Functions state machine that runs a backtest grid (null until enable_backtest_engine = true). Input: {\"configs\": [...], \"run_group_id\": \"<uuid, optional>\"}."
  value       = var.enable_backtest_engine ? module.backtest_ecs[0].state_machine_arn : null
}

output "backtest_ecr_repository_url" {
  description = "ECR repository for the backtest image (docker push target)."
  value       = module.ecr_backtest.repository_url
}

output "backtest_ecr_repository_name" {
  description = "Name of the backtest ECR repository."
  value       = module.ecr_backtest.repository_name
}
