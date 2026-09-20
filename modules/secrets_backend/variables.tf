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

variable "news_calendar_api_key" {
  description = "API key for the external economic news calendar provider used by the backend."
  type        = string
  sensitive   = true
}

variable "backend_ssm_params" {
  description = "Non-sensitive backend configuration parameters, written under /<project>/<environment>/backend/<key>. Key = exact env var name expected by NexusQuantSettings."
  type        = map(string)
  default     = {}
}
