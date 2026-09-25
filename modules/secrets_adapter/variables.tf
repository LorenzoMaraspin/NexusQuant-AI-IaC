variable "project_name" {
  description = "Project name identifier used in resource naming and tags."
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)."
  type        = string
}

variable "secret_recovery_window_days" {
  description = "Days before a deleted secret is permanently removed (0 = force delete immediately, useful in dev)."
  type        = number
  default     = 7
}

variable "adapter_api_key" {
  description = "Shared API key for the MT5 REST adapter."
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub Personal Access Token (PAT) for cloning the private repository."
  type        = string
  sensitive   = true
  default     = ""
}

variable "mt5_password" {
  description = "MetaTrader 5 account password."
  type        = string
  sensitive   = true
}

variable "windows_admin_user" {
  type        = string
  description = "Local Windows admin username for EC2 auto-logon (interactive session for MT5)"
}

variable "windows_admin_password" {
  type        = string
  description = "Local Windows admin password for EC2 auto-logon"
  sensitive   = true
}

variable "db_username" {
  description = "RDS PostgreSQL master username."
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "RDS PostgreSQL master password."
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "PostgreSQL database name."
  type        = string
  default     = "nexusquant"
}

variable "rds_endpoint" {
  description = "RDS instance endpoint (host only, without port). Passed in from the rds module output."
  type        = string
}

variable "mt5_account_number" {
  description = "MetaTrader 5 account number."
  type        = number
}

variable "mt5_server" {
  description = "MetaTrader 5 broker server name."
  type        = string
}

variable "mt5_terminal_path" {
  description = "Path to terminal64.exe on the Windows EC2 instance."
  type        = string
  default     = "C:\\Program Files\\MetaTrader 5\\terminal64.exe"
}

variable "mt5_default_deviation" {
  description = "Slippage tolerance in points for market orders."
  type        = number
  default     = 20
}

variable "log_level_console" {
  description = "Console log level (DEBUG, INFO, WARNING, ERROR)."
  type        = string
  default     = "INFO"
}

variable "log_level_file" {
  description = "File log level."
  type        = string
  default     = "DEBUG"
}
