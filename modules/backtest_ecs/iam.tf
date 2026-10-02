###############################################################################
# Module: backtest_ecs — iam.tf
# Least-privilege IAM for the offline Backtest Engine (ECS Fargate one-off).
# Dedicated roles: nothing is shared with the live trading engine, and the
# backtest can never read live secrets (adapter / backend / MT5).
###############################################################################

data "aws_caller_identity" "current" {}

locals {
  # Single source of truth for the log group name; the aws_cloudwatch_log_group
  # resource (Fase 3) uses the same value, so the IAM ARN below is exact.
  log_group_name = "/ecs/${var.project_name}-backtest"
  log_group_arn  = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:${local.log_group_name}"

  ecs_tasks_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })

  # Cross-region inference profile IDs carry a geo prefix. InvokeModel on such an
  # ID needs the inference-profile ARN (this region/account) AND the underlying
  # foundation-model ARN in any region of the profile's group.
  bedrock_profile_prefix_regex = "^(eu|us|us-gov|apac|global)\\."

  bedrock_profile_ids = [
    for id in var.bedrock_model_ids : id
    if can(regex(local.bedrock_profile_prefix_regex, id))
  ]

  bedrock_direct_model_ids = [
    for id in var.bedrock_model_ids : id
    if !can(regex(local.bedrock_profile_prefix_regex, id))
  ]

  bedrock_base_model_ids = distinct([
    for id in local.bedrock_profile_ids :
    replace(id, "/${local.bedrock_profile_prefix_regex}/", "")
  ])

  bedrock_resources = concat(
    [
      for id in local.bedrock_profile_ids :
      "arn:aws:bedrock:${var.bedrock_region}:${data.aws_caller_identity.current.account_id}:inference-profile/${id}"
    ],
    [
      for id in local.bedrock_direct_model_ids :
      "arn:aws:bedrock:${var.bedrock_region}::foundation-model/${id}"
    ],
    [
      for id in local.bedrock_base_model_ids :
      "arn:aws:bedrock:*::foundation-model/${id}"
    ],
  )
}

# --------------------------------------------------------------------------- #
# Task Role — what the backtest code can do at runtime
# --------------------------------------------------------------------------- #

resource "aws_iam_role" "backtest_task" {
  name               = "${var.project_name}-backtest-task-role-${var.environment}"
  assume_role_policy = local.ecs_tasks_trust

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "backtest_task_s3_read" {
  name = "backtest-history-s3-read"
  role = aws_iam_role.backtest_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "HistoricalObjectsRead"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["arn:aws:s3:::${var.history_s3_bucket_name}/${var.history_s3_prefix}/*"]
      },
      {
        Sid      = "HistoricalBucketList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = ["arn:aws:s3:::${var.history_s3_bucket_name}"]
        Condition = {
          StringLike = { "s3:prefix" = ["${var.history_s3_prefix}/*", var.history_s3_prefix] }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "backtest_task_bedrock" {
  count = length(var.bedrock_model_ids) > 0 ? 1 : 0

  name = "backtest-bedrock-invoke"
  role = aws_iam_role.backtest_task.id

  # Exactly the approved Claude / Llama models — never bedrock:* on "*".
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "BedrockInvokeApprovedModels"
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel"]
      Resource = local.bedrock_resources
    }]
  })
}

# --------------------------------------------------------------------------- #
# Task Execution Role — what ECS/Fargate needs to START the task
# --------------------------------------------------------------------------- #

resource "aws_iam_role" "backtest_execution" {
  name               = "${var.project_name}-backtest-exec-role-${var.environment}"
  assume_role_policy = local.ecs_tasks_trust

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Deliberately NOT AmazonECSTaskExecutionRolePolicy: it grants logs:* on "*"
# and ECR pull on every repository. Scoped equivalents below.
resource "aws_iam_role_policy" "backtest_execution" {
  name = "backtest-execution"
  role = aws_iam_role.backtest_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuthToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPullBacktestImage"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = [var.ecr_repository_arn]
      },
      {
        Sid      = "BacktestDbSecretRead"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [var.backtest_db_secret_arn]
      },
      {
        Sid      = "BacktestLogsWrite"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${local.log_group_arn}:*"]
      }
    ]
  })
}
