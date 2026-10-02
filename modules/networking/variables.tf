variable "project_name" {
  description = "Project name identifier used in resource naming and tags."
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)."
  type        = string
}

variable "aws_region" {
  description = "AWS region for networking resources."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_public_cidr" {
  description = "CIDR for public subnet (NAT gateway)."
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_private_windows_cidr" {
  description = "CIDR for private Windows EC2 subnet."
  type        = string
  default     = "10.0.2.0/24"
}

variable "subnet_private_linux_cidr" {
  description = "CIDR for private Linux backend subnet."
  type        = string
  default     = "10.0.3.0/24"
}

variable "subnet_private_db_a_cidr" {
  description = "CIDR for private RDS subnet in AZ a."
  type        = string
  default     = "10.0.4.0/24"
}

variable "subnet_private_db_b_cidr" {
  description = "CIDR for private RDS subnet in AZ b."
  type        = string
  default     = "10.0.5.0/24"
}

variable "rdp_admin_cidr" {
  description = "CIDR block allowed RDP access to the Windows instance (e.g. admin IP / VPN). Leave empty to disable."
  type        = string
  default     = ""
}

variable "subnet_private_backtest_cidr" {
  description = "CIDR for the isolated private subnet running the Backtest Engine Fargate tasks. Must not overlap with any other subnet and must not be trusted by the MT5 Adapter SG."
  type        = string
  default     = "10.0.6.0/24"
}

variable "backtest_allow_https_egress" {
  description = "Allow the backtest SG HTTPS (443) egress to 0.0.0.0/0 via NAT, needed for ECR API, Secrets Manager, CloudWatch Logs and Bedrock. Set to false only when Interface VPC Endpoints for those services exist."
  type        = bool
  default     = true
}
