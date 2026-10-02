###############################################################################
# Module: backtest_ecs — sfn.tf
# AWS Step Functions (Standard) orchestrating the backtest grid.
# Inline Map: one ecs:runTask.sync Fargate task per config, MaxConcurrency-capped.
# Inline limits: 40 concurrent iterations, 25,000 history events per execution
# (~400 configs per execution with retries). For bigger grids start several
# executions that share the same run_group_id (see the definition's Comment).
###############################################################################

locals {
  sfn_name       = "${var.project_name}-backtest-${var.environment}"
  container_name = "nexusquant-backtest"

  sfn_definition = templatefile("${path.module}/sfn_definition.json.tftpl", {
    grid_bucket          = var.history_s3_bucket_name
    cluster_arn          = aws_ecs_cluster.backtest.arn
    task_definition_arn  = aws_ecs_task_definition.backtest.arn # pinned revision: reproducible runs
    container_name       = local.container_name
    capacity_provider    = var.use_fargate_spot ? "FARGATE_SPOT" : "FARGATE"
    subnet_ids           = [var.subnet_id]
    security_group_ids   = [var.security_group_id]
    max_concurrency      = var.max_concurrency
    task_timeout_seconds = var.task_timeout_seconds
    retry_attempts       = var.task_retry_attempts
  })
}

resource "aws_cloudwatch_log_group" "sfn" {
  # /aws/vendedlogs/ prefix avoids the CloudWatch resource-policy size limit.
  name              = "/aws/vendedlogs/states/${local.sfn_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role" "sfn" {
  name = "${var.project_name}-backtest-sfn-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "states.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "sfn" {
  name = "backtest-sfn-orchestration"
  role = aws_iam_role.sfn.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RunBacktestTasksOnly"
        Effect   = "Allow"
        Action   = ["ecs:RunTask"]
        Resource = ["${aws_ecs_task_definition.backtest.arn_without_revision}:*"]
        Condition = {
          ArnEquals = { "ecs:cluster" = aws_ecs_cluster.backtest.arn }
        }
      },
      {
        Sid    = "ManageBacktestTasks"
        Effect = "Allow"
        Action = ["ecs:StopTask", "ecs:DescribeTasks"]
        Resource = [
          "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task/${aws_ecs_cluster.backtest.name}/*"
        ]
      },
      {
        # The state machine itself reads the grid (JSON list of configs) from S3.
        Sid      = "ReadBacktestGridFromS3"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["arn:aws:s3:::${var.history_s3_bucket_name}/${var.grid_s3_prefix}/*"]
      },
      {
        Sid    = "PassOnlyBacktestRolesToEcs"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          aws_iam_role.backtest_task.arn,
          aws_iam_role.backtest_execution.arn
        ]
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      },
      {
        # Managed rule that Step Functions creates for the .sync integration.
        Sid    = "SyncIntegrationEvents"
        Effect = "Allow"
        Action = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
        Resource = [
          "arn:aws:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rule/StepFunctionsGetEventsForECSTaskRule"
        ]
      },
      {
        Sid    = "StateMachineLogDelivery"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_sfn_state_machine" "backtest" {
  name       = local.sfn_name
  role_arn   = aws_iam_role.sfn.arn
  type       = "STANDARD"
  definition = local.sfn_definition

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = false
    level                  = "ERROR"
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }

  depends_on = [aws_iam_role_policy.sfn]
}
