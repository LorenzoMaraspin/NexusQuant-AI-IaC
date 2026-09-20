output "cluster_id" {
  description = "ID of the ECS cluster."
  value       = aws_ecs_cluster.main.id
}

output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.main.name
}

output "service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.backend.name
}

output "task_definition_arn" {
  description = "ARN of the ECS task definition."
  value       = aws_ecs_task_definition.backend.arn
}

output "security_group_id" {
  description = "Security Group ID of the backend ECS service."
  value       = aws_security_group.backend.id
}
