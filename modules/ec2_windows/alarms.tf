###############################################################################
# CloudWatch alarms for the MT5 adapter EC2 instance.
#
# Only the EC2 system-status-check alarm remains: the NexusQuant/MT5 custom
# metrics (AdapterHealthy, TradeAllowed, MemAvailableMB, DiskFreeGB, ...) were
# published by watchdog.ps1, which was removed when the instance moved back
# to a manual start (RDP in, run C:\nexusquant\bin\start.ps1) with no
# auto-logon, scheduled tasks or self-healing supervision. Re-add alarms here
# if a supervisor script publishing those metrics comes back.
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

# Soft warning (Terraform >= 1.5): a too-small instance is a known cause of adapter hangs.
check "instance_memory" {
  assert {
    condition     = !can(regex("^t[23]a?\\.(nano|micro|small)$", var.instance_type))
    error_message = "instance_type ${var.instance_type} has 2 GiB RAM or less: too small for Windows Server 2022 + MetaTrader 5 + the adapter. Use t3.medium or larger."
  }
}
