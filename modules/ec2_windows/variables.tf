variable "project_name" {
  description = "Project name identifier used in resource naming and tags."
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)."
  type        = string
}

variable "aws_region" {
  description = "AWS region for the EC2 instance."
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the Windows EC2 instance (public subnet for direct RDP, or private subnet)."
  type        = string
}

variable "sg_windows_adapter_id" {
  description = "Security Group ID for the Windows adapter."
  type        = string
}

variable "secret_arn" {
  description = "ARN of the Secrets Manager secret containing MT5 adapter credentials."
  type        = string
}

variable "secret_name" {
  description = "Name of the Secrets Manager secret."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for Windows Server. Windows Server 2022 + MetaTrader 5 + the adapter need at least 4 GiB RAM (t3.medium or larger)."
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GiB. Windows Server 2022 + MT5 + Python + logs do not fit comfortably in 30 GiB."
  type        = number
  default     = 60
}

variable "alarm_action_arns" {
  description = "Optional SNS topic ARNs notified when a MT5 health alarm fires or clears. The EC2 auto-recovery action is always attached to the system-status alarm."
  type        = list(string)
  default     = []
}

variable "key_pair_name" {
  description = "Name of an existing EC2 key pair. If empty, Terraform generates a new 4096-bit RSA key pair."
  type        = string
  default     = ""
}

variable "private_key_secret_recovery_window_days" {
  description = "Days before the deleted EC2 private-key Secrets Manager secret is permanently removed (0 = force delete immediately, needed to freely recreate the key pair under the same name)."
  type        = number
  default     = 0
}

variable "windows_admin_password_override" {
  description = "Local Administrator password to use only when key_pair_name references an existing, externally-managed key pair (Terraform then has no private key in state to decrypt the instance's real password with). Ignored when key_pair_name is empty, since the actual password is decrypted automatically in that case."
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_repo_url" {
  description = "Git clone URL of the MT5 connector repository."
  type        = string
}

variable "repo_branch" {
  description = "Git branch to checkout."
  type        = string
  default     = "main"
}

variable "mt5_installer_url" {
  description = "Public HTTPS URL of the MetaTrader 5 Windows installer (mt5setup.exe)."
  type        = string
  default     = "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days for the EC2 MT5 adapter log group."
  type        = number
  default     = 90
}

variable "cloudwatch_log_group_name" {
  description = "Custom CloudWatch log group name for the EC2 instance. If empty, defaults to /<project_name>/<environment>/mt5-adapter."
  type        = string
  default     = ""
}

variable "history_s3_bucket_name" {
  description = "S3 bucket the MT5 adapter may write historical data exports to. Empty = no S3 permissions are granted."
  type        = string
  default     = ""
}

variable "history_s3_prefix" {
  description = "Key prefix inside history_s3_bucket_name the adapter may write to (no leading/trailing slash)."
  type        = string
  default     = "historical"
}
