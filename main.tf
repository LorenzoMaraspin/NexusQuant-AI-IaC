###############################################################################
# NexusQuant AI — Unified Infrastructure Orchestration
# Root main.tf
###############################################################################

# --------------------------------------------------------------------------- #
# 1. Networking: VPC, Subnets, Gateways, Route Tables, Security Groups
# --------------------------------------------------------------------------- #
module "networking" {
  source = "./modules/networking"

  project_name                = var.project_name
  environment                 = var.environment
  aws_region                  = var.aws_region
  vpc_cidr                    = var.vpc_cidr
  subnet_public_cidr          = var.subnet_public_cidr
  subnet_private_windows_cidr = var.subnet_private_windows_cidr
  subnet_private_linux_cidr   = var.subnet_private_linux_cidr
  subnet_private_db_a_cidr    = var.subnet_private_db_a_cidr
  subnet_private_db_b_cidr    = var.subnet_private_db_b_cidr
  rdp_admin_cidr              = var.rdp_admin_cidr
}

# --------------------------------------------------------------------------- #
# 2. RDS: PostgreSQL 16
# --------------------------------------------------------------------------- #
module "rds" {
  source = "./modules/rds"

  project_name          = var.project_name
  environment           = var.environment
  subnet_ids            = module.networking.subnet_private_db_ids
  sg_rds_id             = module.networking.sg_rds_id
  db_name               = var.db_name
  db_username           = var.db_username
  db_password           = var.db_password
  instance_class        = var.rds_instance_class
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
  multi_az              = var.rds_multi_az
  deletion_protection   = var.rds_deletion_protection
  backup_retention_days = var.rds_backup_retention_days
  publicly_accessible   = var.rds_publicly_accessible
}

# --------------------------------------------------------------------------- #
# 3. Secrets Adapter: Secrets Manager + SSM for MT5 Connector
# --------------------------------------------------------------------------- #
module "secrets_adapter" {
  source = "./modules/secrets_adapter"

  project_name                = var.project_name
  environment                 = var.environment
  secret_recovery_window_days = var.secret_recovery_window_days
  adapter_api_key             = var.adapter_api_key
  mt5_password                = var.mt5_password
  db_username                 = var.db_username
  db_password                 = var.db_password
  db_name                     = var.db_name
  rds_endpoint                = module.rds.endpoint
  mt5_account_number          = var.mt5_account_number
  mt5_server                  = var.mt5_server
  mt5_terminal_path           = var.mt5_terminal_path
  mt5_default_deviation       = var.mt5_default_deviation
  log_level_console           = var.log_level_console
  log_level_file              = var.log_level_file
  github_token                = var.github_token
}

# --------------------------------------------------------------------------- #
# 4. EC2 Windows: MT5 Terminal + REST API Adapter (Server 2022)
# --------------------------------------------------------------------------- #
module "ec2_windows" {
  source = "./modules/ec2_windows"

  project_name              = var.project_name
  environment               = var.environment
  aws_region                = var.aws_region
  subnet_id                 = module.networking.subnet_public_id
  sg_windows_adapter_id     = module.networking.sg_windows_adapter_id
  secret_arn                = module.secrets_adapter.secret_arn
  secret_name               = module.secrets_adapter.secret_name
  instance_type             = var.ec2_instance_type
  key_pair_name             = var.ec2_key_pair_name
  github_repo_url           = var.github_repo_url
  repo_branch               = var.repo_branch
  mt5_installer_url         = var.mt5_installer_url
  log_retention_days        = var.ec2_log_retention_days
  cloudwatch_log_group_name = var.ec2_cloudwatch_log_group_name
}

# --------------------------------------------------------------------------- #
# 5. ECR: Container repository for the NexusQuant AI Backend Image
# --------------------------------------------------------------------------- #
module "ecr" {
  source = "./modules/ecr"

  project_name         = var.project_name
  environment          = var.environment
  max_image_count      = var.ecr_max_image_count
  untagged_expiry_days = var.ecr_untagged_expiry_days
}

# --------------------------------------------------------------------------- #
# 6. Secrets Backend: Secrets Manager + SSM for NexusQuant AI Backend
# --------------------------------------------------------------------------- #
module "secrets_backend" {
  source = "./modules/secrets_backend"

  project_name                = var.project_name
  environment                 = var.environment
  secret_recovery_window_days = var.secret_recovery_window_days
  news_calendar_api_key       = var.news_calendar_api_key

  backend_ssm_params = merge(
    {
      LOG_LEVEL_CONSOLE = var.log_level_console
      LOG_LEVEL_FILE    = var.log_level_file
    },
    var.backend_extra_ssm_params
  )
}

# --------------------------------------------------------------------------- #
# 7. ECS Fargate: NexusQuant AI Backend Service (Singleton Trading Loop)
# --------------------------------------------------------------------------- #
module "ecs_backend" {
  count  = var.enable_ecs_backend ? 1 : 0
  source = "./modules/ecs_backend"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region

  vpc_id                = module.networking.vpc_id
  subnet_id             = module.networking.subnet_private_linux_id
  sg_windows_adapter_id = module.networking.sg_windows_adapter_id
  sg_rds_id             = module.networking.sg_rds_id

  ecr_repository_url = module.ecr.repository_url
  image_tag          = var.backend_image_tag

  task_cpu               = var.backend_task_cpu
  task_memory            = var.backend_task_memory
  log_retention_days     = var.backend_log_retention_days
  enable_execute_command = var.backend_enable_execute_command

  adapter_secret_arn     = module.secrets_adapter.secret_arn
  backend_secret_arn     = module.secrets_backend.secret_arn
  backend_ssm_param_arns = module.secrets_backend.ssm_param_arns

  # Direct wiring from peer modules — no data source lookups needed!
  mt5_adapter_base_url = "http://${module.ec2_windows.private_ip}:8100"
  postgres_host        = module.rds.endpoint
  postgres_port        = tostring(module.rds.port)
  postgres_db          = module.rds.db_name

  # Bedrock — only invoked when LLM_PROVIDER=bedrock (set via
  # backend_extra_ssm_params below); the IAM policy is skipped entirely
  # when bedrock_model_ids is empty.
  bedrock_region    = var.bedrock_region
  bedrock_model_ids = var.bedrock_model_ids
}
