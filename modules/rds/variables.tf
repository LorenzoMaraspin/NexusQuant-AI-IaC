variable "project_name" {
  description = "Project name identifier used in resource naming and tags."
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)."
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs for the RDS subnet group."
  type        = list(string)
}

variable "sg_rds_id" {
  description = "Security Group ID for RDS."
  type        = string
}

variable "db_name" {
  description = "PostgreSQL database name."
  type        = string
  default     = "nexusquant"
}

variable "db_username" {
  description = "PostgreSQL master username."
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "PostgreSQL master password."
  type        = string
  sensitive   = true
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Allocated storage for RDS in GB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum storage for RDS autoscaling in GB."
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Enable Multi-AZ for RDS."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Enable deletion protection on RDS instance."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Days of backup retention for RDS."
  type        = number
  default     = 1
}

variable "publicly_accessible" {
  description = "Whether the RDS instance is publicly accessible."
  type        = bool
  default     = false
}

