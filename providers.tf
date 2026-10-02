provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = "NexusQuant-AI-IaC"
    }
  }
}

# PostgreSQL provider: used ONLY by module.backtest_db (enable_backtest_db = true);
# the connection is lazy, so with the module disabled nothing connects.
# RDS is private (publicly_accessible = false). From a workstation open a tunnel
# through the MT5 adapter instance (its SG is already allowed on 5432):
#
#   aws ssm start-session --target <ec2_windows_instance_id> `
#     --document-name AWS-StartPortForwardingSessionToRemoteHost `
#     --parameters host=<rds_endpoint>,portNumber=5432,localPortNumber=15432
#
# then: terraform apply -var enable_backtest_db=true `
#         -var backtest_db_connect_host=127.0.0.1 -var backtest_db_connect_port=15432
provider "postgresql" {
  host            = var.backtest_db_connect_host != "" ? var.backtest_db_connect_host : module.rds.endpoint
  port            = var.backtest_db_connect_port
  database        = "postgres"
  username        = var.db_username
  password        = var.db_password
  sslmode         = "require"
  superuser       = false # RDS master is rds_superuser, not a real superuser
  connect_timeout = 20
}
