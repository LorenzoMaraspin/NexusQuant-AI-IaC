variable "project_name" {
  description = "Project name used for tagging."
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, prod)."
  type        = string
}

variable "bucket_name" {
  description = "Globally unique name of the S3 bucket."
  type        = string
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete the bucket even if it contains objects."
  type        = bool
  default     = false
}

variable "abort_incomplete_multipart_days" {
  description = "Days after which incomplete multipart uploads are aborted and their parts deleted."
  type        = number
  default     = 7
}
