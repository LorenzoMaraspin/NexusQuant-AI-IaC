###############################################################################
# CloudWatch alarms for the MT5 adapter EC2 instance
# Metrics in namespace NexusQuant/MT5 are published every minute by watchdog.ps1.
###############################################################################

# Instance-level hardware/system failure: automatic recovery onto healthy hardware.
resource "aws_cloudwatch_metric_alarm" "instance_system_check" {
  alarm_name          = "${var.project_name}-${var.environment}-mt5-ec2-system-check-failed"
  alarm_description   = "EC2 system status check failed for the MT5 adapter instance: trigger automatic recovery."
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed_System"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.mt5_adapter.id
  }

  alarm_actions = concat(["arn:aws:automate:${var.aws_region}:ec2:recover"], var.alarm_action_arns)
  ok_actions    = var.alarm_action_arns

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Terminal down or disconnected / adapter unresponsive for 5 consecutive minutes.
# Missing data counts as breaching: a dead watchdog or instance must also alarm.
resource "aws_cloudwatch_metric_alarm" "adapter_unhealthy" {
  alarm_name          = "${var.project_name}-${var.environment}-mt5-adapter-unhealthy"
  alarm_description   = "MT5 terminal not running/connected or adapter not answering /health for 5 minutes."
  namespace           = "NexusQuant/MT5"
  metric_name         = "AdapterHealthy"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    Environment = var.environment
  }

  alarm_actions = var.alarm_action_arns
  ok_actions    = var.alarm_action_arns

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# AutoTrading disabled in the terminal (only published when the adapter exposes trade_allowed).
resource "aws_cloudwatch_metric_alarm" "autotrading_disabled" {
  alarm_name          = "${var.project_name}-${var.environment}-mt5-autotrading-disabled"
  alarm_description   = "MT5 reports trade_allowed=false for 5 minutes: orders would be rejected."
  namespace           = "NexusQuant/MT5"
  metric_name         = "TradeAllowed"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Environment = var.environment
  }

  alarm_actions = var.alarm_action_arns
  ok_actions    = var.alarm_action_arns

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Resource exhaustion on the Windows host (the usual cause of an adapter that hangs).
resource "aws_cloudwatch_metric_alarm" "low_memory" {
  alarm_name          = "${var.project_name}-${var.environment}-mt5-low-memory"
  alarm_description   = "Less than 300 MB of free RAM on the MT5 adapter host for 5 minutes."
  namespace           = "NexusQuant/MT5"
  metric_name         = "MemAvailableMB"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  threshold           = 300
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Environment = var.environment
  }

  alarm_actions = var.alarm_action_arns
  ok_actions    = var.alarm_action_arns

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "low_disk" {
  alarm_name          = "${var.project_name}-${var.environment}-mt5-low-disk"
  alarm_description   = "Less than 5 GB free on C: of the MT5 adapter host."
  namespace           = "NexusQuant/MT5"
  metric_name         = "DiskFreeGB"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 5
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Environment = var.environment
  }

  alarm_actions = var.alarm_action_arns
  ok_actions    = var.alarm_action_arns

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Soft warning (Terraform >= 1.5): a too-small instance is a known cause of adapter hangs.
check "instance_memory" {
  assert {
    condition     = !can(regex("^t[23]a?\\.(nano|micro|small)$", var.instance_type))
    error_message = "instance_type ${var.instance_type} has 2 GiB RAM or less: too small for Windows Server 2022 + MetaTrader 5 + the adapter. Use t3.medium or larger."
  }
}
