variable "project_name" {
  description = "Project name identifier used in resource naming and tags."
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)."
  type        = string
}

variable "max_image_count" {
  description = "Maximum tagged images to retain in the backend ECR repository."
  type        = number
  default     = 15
}

variable "untagged_expiry_days" {
  description = "Days after which untagged ECR images are expired."
  type        = number
  default     = 7
}
