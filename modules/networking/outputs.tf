output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.main.id
}

output "subnet_public_id" {
  description = "ID of the public subnet (NAT GW)."
  value       = aws_subnet.public.id
}

output "subnet_private_windows_id" {
  description = "ID of the private subnet for the Windows EC2 adapter."
  value       = aws_subnet.private_windows.id
}

output "subnet_private_linux_id" {
  description = "ID of the private subnet for the Linux backend."
  value       = aws_subnet.private_linux.id
}

output "subnet_private_db_ids" {
  description = "IDs of the two DB subnets (for the RDS subnet group)."
  value       = [aws_subnet.private_db_a.id, aws_subnet.private_db_b.id]
}

output "sg_windows_adapter_id" {
  description = "Security Group ID for the Windows adapter."
  value       = aws_security_group.windows_adapter.id
}

output "sg_rds_id" {
  description = "Security Group ID for RDS."
  value       = aws_security_group.rds.id
}

output "subnet_private_backtest_id" {
  description = "ID of the isolated private subnet for the Backtest Engine tasks."
  value       = aws_subnet.private_backtest.id
}

output "route_table_private_backtest_id" {
  description = "ID of the route table of the backtest subnet (associated with the S3 Gateway Endpoint)."
  value       = aws_route_table.private_backtest.id
}

output "sg_backtest_id" {
  description = "Security Group ID for the Backtest Engine tasks."
  value       = aws_security_group.backtest.id
}

output "vpc_endpoint_s3_id" {
  description = "ID of the S3 Gateway VPC Endpoint."
  value       = aws_vpc_endpoint.s3.id
}

output "s3_prefix_list_id" {
  description = "Managed prefix list ID of the S3 Gateway Endpoint."
  value       = aws_vpc_endpoint.s3.prefix_list_id
}
