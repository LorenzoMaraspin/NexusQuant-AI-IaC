###############################################################################
# Module: rds — RDS PostgreSQL 16
###############################################################################

resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-rds-subnet-group-${var.environment}"
  description = "Subnet group for NexusQuant RDS PostgreSQL"
  subnet_ids  = var.subnet_ids

  tags = {
    Name        = "${var.project_name}-rds-subnet-group-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_db_parameter_group" "postgres16" {
  name        = "${var.project_name}-pg16-${var.environment}"
  family      = "postgres16"
  description = "Custom parameter group for NexusQuant PostgreSQL 16"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-rds-${var.environment}"

  engine                = "postgres"
  engine_version        = "16.9"
  instance_class        = var.instance_class
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.sg_rds_id]
  parameter_group_name   = aws_db_parameter_group.postgres16.name

  multi_az                  = var.multi_az
  publicly_accessible       = var.publicly_accessible
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = true
  final_snapshot_identifier = var.deletion_protection ? "${var.project_name}-rds-final-${var.environment}" : null

  backup_retention_period = var.backup_retention_days
  backup_window           = var.backup_retention_days > 0 ? "03:00-04:00" : null
  maintenance_window      = "Mon:04:00-Mon:05:00"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  tags = {
    Name        = "${var.project_name}-rds-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}
