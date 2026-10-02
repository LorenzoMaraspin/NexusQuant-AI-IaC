###############################################################################
# Module: backtest_ecs — main.tf
# ECS cluster + Task Definition for the offline Backtest Engine.
# One-off tasks only: there is intentionally NO aws_ecs_service. Tasks are
# launched by Step Functions (ecs:runTask.sync) — see Fase 4.
###############################################################################

resource "aws_cloudwatch_log_group" "backtest" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Dedicated cluster: isolated from the live trading cluster (no shared quotas,
# metrics or IAM scoping).
resource "aws_ecs_cluster" "backtest" {
  name = "${var.project_name}-backtest-${var.environment}"

  # Short-lived batch tasks: Container Insights would only add cost.
  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Name        = "${var.project_name}-backtest-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_ecs_cluster_capacity_providers" "backtest" {
  cluster_name       = aws_ecs_cluster.backtest.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = var.use_fargate_spot ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
  }
}

locals {
  container_environment = concat(
    [
      { name = "POSTGRES_HOST", value = var.postgres_host },
      { name = "POSTGRES_PORT", value = tostring(var.postgres_port) },
      { name = "POSTGRES_DB", value = var.postgres_db },
      { name = "BACKTEST_S3_BUCKET", value = var.history_s3_bucket_name },
      { name = "AWS_REGION", value = var.aws_region },
      # BACKTEST_CONFIG_JSON and BACKTEST_RUN_GROUP_ID are deliberately NOT set
      # here: Step Functions injects them per grid element (containerOverrides).
      # Per-agent model names travel inside the config (settings_overrides).
    ],
    [for k, v in var.extra_environment : { name = k, value = v }],
  )

  # Only the backtest DB credentials are injected. No adapter key, MT5 password,
  # news API key or any other live secret — and no MT5_ADAPTER_BASE_URL.
  container_secrets = [
    { name = "POSTGRES_USER", valueFrom = "${var.backtest_db_secret_arn}:DB_USERNAME::" },
    { name = "POSTGRES_PASSWORD", valueFrom = "${var.backtest_db_secret_arn}:DB_PASSWORD::" },
  ]

  entrypoint_override = { for k, v in { entryPoint = var.container_entrypoint } : k => v if length(var.container_entrypoint) > 0 }
}

resource "aws_ecs_task_definition" "backtest" {
  family                   = "${var.project_name}-backtest-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.task_cpu)
  memory                   = tostring(var.task_memory)
  execution_role_arn       = aws_iam_role.backtest_execution.arn
  task_role_arn            = aws_iam_role.backtest_task.arn

  ephemeral_storage {
    size_in_gib = var.ephemeral_storage_gib
  }

  container_definitions = jsonencode([
    merge(
      {
        name        = local.container_name
        image       = "${var.ecr_repository_url}:${var.image_tag}"
        essential   = true
        command     = var.container_command
        environment = local.container_environment
        secrets     = local.container_secrets

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.backtest.name
            "awslogs-region"        = var.aws_region
            "awslogs-stream-prefix" = "backtest"
          }
        }
      },
      local.entrypoint_override
    )
  ])

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }

  lifecycle {
    # The live image's ENTRYPOINT starts the trading loop: never run it here.
    precondition {
      condition     = var.live_image_tag == "" || var.image_tag != var.live_image_tag
      error_message = "backtest_image_tag must be a dedicated backtest image (Dockerfile.backtest, e.g. backtest-<git-sha>), not the live backend tag."
    }
  }
}
