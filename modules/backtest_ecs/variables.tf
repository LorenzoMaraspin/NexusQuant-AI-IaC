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

variable "history_s3_bucket_name" {
  description = "S3 bucket holding the historical Parquet datasets (read-only for the backtest task role)."
  type        = string

  validation {
    condition     = var.history_s3_bucket_name != ""
    error_message = "history_s3_bucket_name must be set: the backtest task needs the historical dataset bucket."
  }
}

variable "history_s3_prefix" {
  description = "Key prefix inside the history bucket that the backtest may read."
  type        = string
  default     = "historical"
}

variable "bedrock_region" {
  description = "Region where Bedrock is invoked (scopes the model ARNs in the task role policy)."
  type        = string
  default     = "eu-north-1"
}

variable "bedrock_model_ids" {
  description = "Bedrock model IDs (Claude / Llama) the backtest task role may invoke. Plain foundation-model IDs or geo-prefixed inference profile IDs (eu., us., apac., global.). Empty = no Bedrock policy (pure-quant backtests without LLM calls)."
  type        = list(string)
  default     = []
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repository the execution role may pull the backtest image from."
  type        = string
}

variable "backtest_db_secret_arn" {
  description = "ARN of the Secrets Manager secret with the nexusquant_backtest DB credentials (module.backtest_db). Requires enable_backtest_db = true."
  type        = string

  validation {
    condition     = var.backtest_db_secret_arn != null && var.backtest_db_secret_arn != ""
    error_message = "backtest_db_secret_arn is empty: set enable_backtest_db = true so the backtest DB secret exists."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the backtest log group."
  type        = number
  default     = 14
}

# --- Fase 3: compute ---

variable "ecr_repository_url" {
  description = "ECR repository URL of the image run by the backtest task (same codebase as the live engine)."
  type        = string
}

variable "image_tag" {
  description = "Immutable tag of the BACKTEST image (built from Dockerfile.backtest), e.g. backtest-<git-sha>."
  type        = string

  validation {
    condition     = var.image_tag != ""
    error_message = "image_tag is empty: set backtest_image_tag to the tag of the Dockerfile.backtest image (e.g. backtest-<git-sha>)."
  }
}

variable "live_image_tag" {
  description = "Tag of the live backend image. Used only as a guard: the backtest task must never run it."
  type        = string
  default     = ""
}

variable "task_cpu" {
  description = "Fargate vCPU units (4096 = 4 vCPU)."
  type        = number
  default     = 4096
}

variable "task_memory" {
  description = "Fargate memory in MiB (16384 = 16 GB): pandas multiprocessing is RAM-hungry."
  type        = number
  default     = 16384
}

variable "ephemeral_storage_gib" {
  description = "Fargate ephemeral storage in GiB (20-200) for Parquet files and temp data."
  type        = number
  default     = 30
}

variable "container_command" {
  description = "Container command (appended to the image ENTRYPOINT)."
  type        = list(string)
  default     = ["--log-level=ERROR"]
}

variable "container_entrypoint" {
  description = "Optional ENTRYPOINT override (e.g. [\"python\", \"-m\", \"app.backtest\"]). Empty = use the image's ENTRYPOINT."
  type        = list(string)
  default     = []
}

variable "postgres_host" {
  description = "RDS endpoint hostname."
  type        = string
}

variable "postgres_port" {
  description = "RDS port."
  type        = number
  default     = 5432
}

variable "postgres_db" {
  description = "Backtest logical database name (POSTGRES_DB)."
  type        = string
}

variable "extra_environment" {
  description = "Additional NON-secret environment variables for the container (e.g. per-agent model names). Never put live keys or secrets here."
  type        = map(string)
  default     = {}
}

variable "use_fargate_spot" {
  description = "Run backtest tasks on FARGATE_SPOT (~70% cheaper, but an interrupted task restarts from scratch) instead of on-demand FARGATE. Default false: safer for long backtests."
  type        = bool
  default     = false
}

# --- Fase 4: orchestration ---

variable "subnet_id" {
  description = "Isolated backtest subnet where the Fargate tasks run."
  type        = string
}

variable "security_group_id" {
  description = "Backtest Security Group attached to the tasks."
  type        = string
}

variable "max_concurrency" {
  description = "Max parallel backtest tasks (Map MaxConcurrency, inline cap 40). Bounds RDS connections (~2 per task vs the role limit of 40) and Bedrock rate limits. Assumes --workers 1 per task."
  type        = number
  default     = 10

  validation {
    condition     = var.max_concurrency >= 1 && var.max_concurrency <= 40
    error_message = "max_concurrency must be between 1 and 40 (Inline Map limit)."
  }
}

variable "task_timeout_seconds" {
  description = "Hard timeout of a single backtest task (Step Functions stops the ECS task when exceeded)."
  type        = number
  default     = 21600
}

variable "task_retry_attempts" {
  description = "Retries per config on task failure / Spot interruption. Safe: the CLI closes unfinished attempts of the same run_group_id + name as FAILED, and trades are written in one transaction at the end."
  type        = number
  default     = 2
}
