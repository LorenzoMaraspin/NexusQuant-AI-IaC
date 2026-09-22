variable "project_name" {
  description = "Project name identifier used in resource naming and tags."
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)."
  type        = string
}

variable "aws_region" {
  description = "AWS region."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the backend service runs."
  type        = string
}

variable "subnet_id" {
  description = "Private Linux subnet ID for the ECS task, awsvpc network mode."
  type        = string
}

variable "sg_windows_adapter_id" {
  description = "Security Group ID of the Windows MT5 adapter."
  type        = string
}

variable "sg_rds_id" {
  description = "Security Group ID of RDS."
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR repository URL for the backend image."
  type        = string
}

variable "image_tag" {
  description = "Immutable tag of the backend image to deploy (e.g. a git short SHA)."
  type        = string
}

variable "task_cpu" {
  description = "Fargate task vCPU units (512 = 0.5 vCPU)."
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "Fargate task memory in MB."
  type        = number
  default     = 1024
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the backend log group."
  type        = number
  default     = 90
}

variable "enable_execute_command" {
  description = "Enable ECS Exec (aws ecs execute-command) for interactive troubleshooting of the running task."
  type        = bool
  default     = true
}

variable "adapter_secret_arn" {
  description = "ARN of the MT5 Adapter Secrets Manager secret."
  type        = string
}

variable "backend_secret_arn" {
  description = "ARN of the backend-specific Secrets Manager secret (NEWS_CALENDAR_API_KEY)."
  type        = string
}

variable "backend_ssm_param_arns" {
  description = "Map of backend SSM parameter name to ARN, from module.secrets_backend."
  type        = map(string)
  default     = {}
}

variable "mt5_adapter_base_url" {
  description = "Base URL of the MT5 Adapter REST API, computed from the EC2 Windows instance's private IP."
  type        = string
}

variable "postgres_host" {
  description = "RDS PostgreSQL endpoint hostname."
  type        = string
}

variable "postgres_port" {
  description = "RDS PostgreSQL port."
  type        = string
}

variable "postgres_db" {
  description = "PostgreSQL database name."
  type        = string
}

variable "bedrock_region" {
  description = "AWS region to invoke Amazon Bedrock in (used only to scope the task role's bedrock:InvokeModel policy — the backend's own BEDROCK_REGION env var, set via backend_ssm_params, is what the application actually uses at runtime)."
  type        = string
  default     = "eu-north-1"
}

variable "bedrock_model_ids" {
  description = "Bedrock foundation model IDs the ECS task role is allowed to invoke (e.g. \"amazon.nova-lite-v1:0\"). The IAM policy is scoped to exactly these model ARNs — never bedrock:* on Resource \"*\". Leave empty to skip creating the policy (e.g. when LLM_PROVIDER=ollama and Bedrock is not used)."
  type        = list(string)
  default     = []
}
