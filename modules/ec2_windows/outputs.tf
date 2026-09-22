output "instance_id" {
  description = "EC2 instance ID of the Windows MT5 adapter."
  value       = aws_instance.mt5_adapter.id
}

output "private_ip" {
  description = "Private IP address of the Windows EC2 instance (used by the Linux backend)."
  value       = aws_instance.mt5_adapter.private_ip
}

output "public_ip" {
  description = "Public IP address of the Windows EC2 instance for direct RDP connection."
  value       = aws_instance.mt5_adapter.public_ip
}

output "iam_role_arn" {
  description = "ARN of the IAM Role attached to the EC2 instance."
  value       = aws_iam_role.ec2_windows.arn
}

output "key_pair_name" {
  description = "Name of the EC2 key pair used by the Windows instance."
  value       = local.effective_key_pair_name
}

output "private_key_pem" {
  description = "Private key material for the auto-generated EC2 key pair. Sensitive and kept in Terraform state."
  value       = var.key_pair_name == "" ? tls_private_key.ec2_windows[0].private_key_pem : null
  sensitive   = true
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for the EC2 instance and MT5 adapter."
  value       = aws_cloudwatch_log_group.adapter.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for the EC2 instance and MT5 adapter."
  value       = aws_cloudwatch_log_group.adapter.arn
}

output "ssm_bootstrap_document_name" {
  description = "Name of the SSM Document used to bootstrap the EC2 instance."
  value       = aws_ssm_document.bootstrap.name
}
