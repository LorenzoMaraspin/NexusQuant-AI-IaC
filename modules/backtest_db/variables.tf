variable "project_name" {
  description = "Project name identifier used in resource naming and tags."
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)."
  type        = string
}

variable "backtest_db_name" {
  description = "Name of the logical database for backtest reporting."
  type        = string
  default     = "nexusquant_backtest"
}

variable "backtest_db_username" {
  description = "Dedicated login role for the backtest containers."
  type        = string
  default     = "nexusquant_backtest_user"
}

variable "secret_recovery_window_days" {
  description = "Days before a deleted secret is permanently removed (0 = force delete immediately)."
  type        = number
  default     = 7
}
