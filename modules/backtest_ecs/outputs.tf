output "task_role_arn" {
  description = "ARN of the backtest ECS task role."
  value       = aws_iam_role.backtest_task.arn
}

output "execution_role_arn" {
  description = "ARN of the backtest ECS task execution role."
  value       = aws_iam_role.backtest_execution.arn
}

output "log_group_name" {
  description = "Name of the backtest CloudWatch log group (created in Fase 3)."
  value       = local.log_group_name
}

output "cluster_arn" {
  description = "ARN of the backtest ECS cluster."
  value       = aws_ecs_cluster.backtest.arn
}

output "cluster_name" {
  description = "Name of the backtest ECS cluster."
  value       = aws_ecs_cluster.backtest.name
}

output "task_definition_arn" {
  description = "ARN of the task definition revision (pinned)."
  value       = aws_ecs_task_definition.backtest.arn
}

output "task_definition_family_arn" {
  description = "Task definition ARN without revision (resolves to the latest ACTIVE revision)."
  value       = aws_ecs_task_definition.backtest.arn_without_revision
}

output "use_fargate_spot" {
  description = "Whether the cluster default capacity provider is FARGATE_SPOT."
  value       = var.use_fargate_spot
}

output "state_machine_arn" {
  description = "ARN of the backtest Step Functions state machine."
  value       = aws_sfn_state_machine.backtest.arn
}

output "state_machine_name" {
  description = "Name of the backtest Step Functions state machine."
  value       = aws_sfn_state_machine.backtest.name
}
