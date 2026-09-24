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
