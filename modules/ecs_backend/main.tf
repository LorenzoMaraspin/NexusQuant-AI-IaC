###############################################################################
# Module: ecs_backend — ECS Fargate service running the NexusQuant AI trading
# loop. Headless singleton worker: no ingress, no load balancer.
###############################################################################

data "aws_caller_identity" "current" {}

# --- ECS Cluster ---

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-backend-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "${var.project_name}-backend-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# --- Security Group ---
# No ingress: the backend is a pure outbound worker and never accepts connections.

resource "aws_security_group" "backend" {
  name        = "${var.project_name}-sg-ecs-backend-${var.environment}"
  description = "NexusQuant AI backend (ECS Fargate trading loop) - outbound only, no ingress"
  vpc_id      = var.vpc_id

  egress {
    description = "All outbound (ECR, Secrets Manager, SSM, CloudWatch, MT5 Adapter REST, RDS, external APIs via NAT)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-sg-ecs-backend-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# --- IAM: Task Execution Role ---

resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-ecs-task-execution-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "backend-secrets-access"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          var.adapter_secret_arn,
          "${var.adapter_secret_arn}*",
          var.backend_secret_arn,
          "${var.backend_secret_arn}*",
        ]
      },
      {
        Sid      = "SSMParameterRead"
        Effect   = "Allow"
        Action   = ["ssm:GetParameters"]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project_name}/${var.environment}/backend/*"
      }
    ]
  })
}

# --- IAM: Task Role ---

resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-ecs-task-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_role_policy" "ecs_task_metrics" {
  name = "backend-cloudwatch-metrics"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "CloudWatchMetrics"
      Effect   = "Allow"
      Action   = ["cloudwatch:PutMetricData"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_history_read" {
  count = var.history_s3_bucket_name != "" ? 1 : 0

  name = "backend-history-s3-read"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "HistoryObjectsRead"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["arn:aws:s3:::${var.history_s3_bucket_name}/${var.history_s3_prefix}/*"]
      },
      {
        Sid       = "HistoryBucketList"
        Effect    = "Allow"
        Action    = ["s3:ListBucket"]
        Resource  = ["arn:aws:s3:::${var.history_s3_bucket_name}"]
        Condition = { StringLike = { "s3:prefix" = ["${var.history_s3_prefix}/*", var.history_s3_prefix] } }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_task_exec" {
  count = var.enable_execute_command ? 1 : 0

  name = "backend-ecs-exec"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "SsmMessages"
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ]
      Resource = "*"
    }]
  })
}

locals {
  # Cross-region inference profile IDs carry a geo prefix (eu., us., apac., global.).
  # Converse/InvokeModel on such an ID needs BOTH:
  #   1) the inference-profile ARN in the caller's region/account, and
  #   2) the underlying foundation-model ARN in ANY region (the profile routes
  #      the request to whichever region of the group serves it).
  # Plain foundation model IDs only need the regional foundation-model ARN.
  bedrock_profile_prefix_regex = "^(eu|us|us-gov|apac|global)\\."

  bedrock_profile_ids = [
    for id in var.bedrock_model_ids : id
    if can(regex(local.bedrock_profile_prefix_regex, id))
  ]

  bedrock_base_model_ids = distinct([
    for id in var.bedrock_model_ids :
    replace(id, "/${local.bedrock_profile_prefix_regex}/", "")
  ])

  bedrock_direct_model_ids = [
    for id in var.bedrock_model_ids : id
    if !can(regex(local.bedrock_profile_prefix_regex, id))
  ]

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
      if length(local.bedrock_profile_ids) > 0
    ],
  )
}

resource "aws_iam_role_policy" "ecs_task_bedrock" {
  count = length(var.bedrock_model_ids) > 0 ? 1 : 0

  name = "backend-bedrock-invoke"
  role = aws_iam_role.ecs_task.id

  # Scoped to the exact approved model IDs — never "bedrock:*" on
  # Resource "*". Update var.bedrock_model_ids to change which models
  # the LLM agent nodes are allowed to invoke in production. IDs with a
  # geo prefix (e.g. "eu.amazon.nova-lite-v1:0") automatically get the
  # inference-profile ARN plus the wildcard-region foundation-model ARN.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "BedrockInvokeApprovedModels"
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ]
      Resource = local.bedrock_resources
    }]
  })
}

# --- CloudWatch Log Group ---

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/nexusquant/backend"
  retention_in_days = var.log_retention_days

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# --- Task Definition ---

locals {
  secrets_manager_entries = [
    { name = "MT5_ADAPTER_API_KEY", valueFrom = "${var.adapter_secret_arn}:ADAPTER_API_KEY::" },
    { name = "POSTGRES_USER", valueFrom = "${var.adapter_secret_arn}:DB_USERNAME::" },
    { name = "POSTGRES_PASSWORD", valueFrom = "${var.adapter_secret_arn}:DB_PASSWORD::" },
    { name = "NEWS_CALENDAR_API_KEY", valueFrom = "${var.backend_secret_arn}:NEWS_CALENDAR_API_KEY::" },
  ]

  ssm_entries = [
    for k, arn in var.backend_ssm_param_arns : { name = k, valueFrom = arn }
  ]

  container_secrets = concat(local.secrets_manager_entries, local.ssm_entries)

  container_environment = [
    { name = "MT5_ADAPTER_BASE_URL", value = var.mt5_adapter_base_url },
    { name = "POSTGRES_HOST", value = var.postgres_host },
    { name = "POSTGRES_PORT", value = var.postgres_port },
    { name = "POSTGRES_DB", value = var.postgres_db },
  ]
}

resource "aws_ecs_task_definition" "backend" {
  family                   = "${var.project_name}-backend-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.task_cpu)
  memory                   = tostring(var.task_memory)
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "nexusquant-backend"
      image     = "${var.ecr_repository_url}:${var.image_tag}"
      essential = true

      environment = local.container_environment
      secrets     = local.container_secrets

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "backend"
        }
      }
    }
  ])

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# --- Service ---
# desired_count is singleton (1).
# deployment_maximum_percent=100 / deployment_minimum_healthy_percent=0 stops the old
# task before starting the new one to prevent parallel trading loops.

resource "aws_ecs_service" "backend" {
  name            = "${var.project_name}-backend-${var.environment}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }

  deployment_maximum_percent         = 100
  deployment_minimum_healthy_percent = 0

  enable_execute_command = var.enable_execute_command

  network_configuration {
    subnets          = [var.subnet_id]
    security_groups  = [aws_security_group.backend.id]
    assign_public_ip = false
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }

  depends_on = [
    aws_ecs_cluster_capacity_providers.main,
    aws_iam_role_policy.ecs_task_execution_secrets,
  ]
}
