###############################################################################
# Root Terraform Variables — NexusQuant Infrastructure as Code
###############################################################################

# =============================================================================
# 1. General Project & Environment
# =============================================================================

variable "project_name" {
  description = "Project name identifier used in resource naming and tags."
  type        = string
  default     = "nexusquant"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for all infrastructure resources."
  type        = string
  default     = "eu-north-1"
}

# =============================================================================
# 2. Networking (VPC, Subnets, Gateways, SGs)
# =============================================================================

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_public_cidr" {
  description = "CIDR block for the public subnet (NAT gateway)."
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_private_windows_cidr" {
  description = "CIDR block for the private Windows EC2 subnet."
  type        = string
  default     = "10.0.2.0/24"
}

variable "subnet_private_linux_cidr" {
  description = "CIDR block for the private Linux backend subnet (ECS Fargate)."
  type        = string
  default     = "10.0.3.0/24"
}

variable "subnet_private_db_a_cidr" {
  description = "CIDR block for private RDS subnet in AZ a."
  type        = string
  default     = "10.0.4.0/24"
}

variable "subnet_private_db_b_cidr" {
  description = "CIDR block for private RDS subnet in AZ b."
  type        = string
  default     = "10.0.5.0/24"
}

variable "rdp_admin_cidr" {
  description = "CIDR block allowed RDP access to the Windows instance (e.g. your admin IP/32 or VPN). Leave empty to disable."
  type        = string
  default     = ""
}

# =============================================================================
# 3. RDS PostgreSQL Database
# =============================================================================

variable "db_name" {
  description = "PostgreSQL database name."
  type        = string
  default     = "nexusquant"
}

variable "db_username" {
  description = "PostgreSQL master username."
  type        = string
  default     = "nexusadmin"
  sensitive   = true
}

variable "db_password" {
  description = "PostgreSQL master password."
  type        = string
  sensitive   = true

  validation {
    condition = (
      can(regex("^[!-~]+$", var.db_password)) &&
      !can(regex("[/@\" ]", var.db_password))
    )
    error_message = "db_password must contain only printable ASCII characters and must not contain '/', '@', '\"', or spaces."
  }
}

variable "rds_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "Allocated storage for RDS in GB."
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Maximum storage for RDS autoscaling in GB."
  type        = number
  default     = 20
}

variable "rds_multi_az" {
  description = "Enable Multi-AZ deployment for RDS."
  type        = bool
  default     = false
}

variable "rds_deletion_protection" {
  description = "Enable deletion protection on the RDS instance."
  type        = bool
  default     = false
}

variable "rds_backup_retention_days" {
  description = "Backup retention period in days for RDS."
  type        = number
  default     = 1
}

variable "rds_publicly_accessible" {
  description = "Whether the RDS instance is publicly accessible."
  type        = bool
  default     = true
}


# =============================================================================
# 4. Secrets & MT5 Connector Configuration
# =============================================================================

variable "secret_recovery_window_days" {
  description = "Secrets Manager recovery window days (0 for immediate deletion in dev testing)."
  type        = number
  default     = 7
}

variable "adapter_api_key" {
  description = "API key required to authenticate against the MT5 adapter REST endpoints."
  type        = string
  sensitive   = true
}

variable "mt5_account_number" {
  description = "MetaTrader 5 account number."
  type        = number
}

variable "mt5_server" {
  description = "MetaTrader 5 broker server name."
  type        = string
}

variable "mt5_password" {
  description = "MetaTrader 5 account password."
  type        = string
  sensitive   = true
}

variable "mt5_terminal_path" {
  description = "Path to terminal64.exe on the Windows machine."
  type        = string
  default     = "C:\\Program Files\\MetaTrader 5\\terminal64.exe"
}

variable "mt5_installer_url" {
  description = "Public HTTPS URL of the MetaTrader 5 Windows installer (mt5setup.exe). Defaults to MetaQuotes' official universal installer, which works with any broker server (the broker is selected/logged into after install, not baked into the installer) and installs to mt5_terminal_path's default location when run with /auto and no /path override. Override only if your broker requires its own branded installer."
  type        = string
  default     = "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"
}

variable "mt5_default_deviation" {
  description = "Default slippage deviation in points."
  type        = number
  default     = 20
}

variable "log_level_console" {
  description = "Console log level (DEBUG, INFO, WARNING, ERROR)."
  type        = string
  default     = "INFO"
}

variable "log_level_file" {
  description = "File log level (DEBUG, INFO, WARNING, ERROR)."
  type        = string
  default     = "DEBUG"
}

# =============================================================================
# 5. EC2 Windows Server (MT5 Terminal & REST Adapter)
# =============================================================================

variable "ec2_instance_type" {
  description = "EC2 instance type for the Windows machine."
  type        = string
  default     = "t3.micro"
}

variable "ec2_key_pair_name" {
  description = "EC2 key pair name for RDP access. Leave empty to auto-create one for the Windows instance."
  type        = string
  default     = ""
}

variable "github_repo_url" {
  description = "Git clone URL of the MT5 connector repository."
  type        = string
  default     = "https://github.com/LorenzoMaraspin/NexusQuant-MT5-Connector.git"
}

variable "github_token" {
  description = "GitHub Personal Access Token (PAT) for cloning the private MT5 Connector repository."
  type        = string
  sensitive   = true
  default     = ""
}

variable "repo_branch" {
  description = "Branch to checkout on the Windows instance."
  type        = string
  default     = "main"
}

variable "ec2_log_retention_days" {
  description = "CloudWatch Logs retention in days for the EC2 MT5 adapter."
  type        = number
  default     = 90
}

variable "ec2_cloudwatch_log_group_name" {
  description = "Custom CloudWatch log group name for the EC2 instance. Leave empty to use /<project_name>/<environment>/mt5-adapter."
  type        = string
  default     = ""
}

# =============================================================================
# 6. Backend Secrets & SSM Parameters (NexusQuant AI)
# =============================================================================

variable "news_calendar_api_key" {
  description = "API key for the external economic news calendar provider used by the backend."
  type        = string
  sensitive   = true
}

variable "backend_extra_ssm_params" {
  description = "Additional non-sensitive backend config parameters (risk thresholds, LLM settings, trading params), written under /<project>/<environment>/backend/<key>."
  type        = map(string)
  default     = {}
}

# =============================================================================
# 7. ECR (Docker Image Repository)
# =============================================================================

variable "ecr_max_image_count" {
  description = "Maximum tagged images to retain in the backend ECR repository."
  type        = number
  default     = 15
}

variable "ecr_untagged_expiry_days" {
  description = "Days after which untagged ECR images are expired."
  type        = number
  default     = 7
}

# =============================================================================
# 8. ECS Fargate Backend (Trading Loop Service)
# =============================================================================

variable "enable_ecs_backend" {
  description = "Toggle to deploy the ECS backend service. Set to false for Day-0 apply before the first Docker image is pushed to ECR."
  type        = bool
  default     = true
}

variable "backend_image_tag" {
  description = "Immutable tag of the backend image to deploy (e.g. git short SHA). Required when enable_ecs_backend is true."
  type        = string
  default     = "latest"
}

variable "backend_task_cpu" {
  description = "Fargate task vCPU units for the backend (512 = 0.5 vCPU)."
  type        = number
  default     = 512
}

variable "backend_task_memory" {
  description = "Fargate task memory in MB for the backend."
  type        = number
  default     = 1024
}

variable "backend_log_retention_days" {
  description = "CloudWatch Logs retention in days for the backend service."
  type        = number
  default     = 90
}

variable "backend_enable_execute_command" {
  description = "Enable ECS Exec for interactive troubleshooting of the running backend task."
  type        = bool
  default     = true
}
