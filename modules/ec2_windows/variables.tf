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
  description = "EC2 instance type for Windows Server."
  type        = string
  default     = "t3.micro"
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
  description = "Public HTTPS URL of the MetaTrader 5 Windows installer (mt5setup.exe), downloaded and silently installed (/auto) during bootstrap instead of requiring a manual RDP session."
  type        = string
  default     = "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"
}
