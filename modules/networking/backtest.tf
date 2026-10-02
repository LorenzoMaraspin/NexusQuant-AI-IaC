###############################################################################
# Module: networking — backtest.tf
# Isolated network slice for the offline Backtest Engine (ECS Fargate one-off
# tasks orchestrated by Step Functions).
#
# Isolation layers (defence in depth) against the MT5 Adapter (TCP 8100):
#   1. Dedicated subnet: its CIDR is NOT in any ingress rule of the adapter SG
#      (the adapter only trusts the Linux backend subnet + admin IP).
#   2. Dedicated Security Group: no ingress, egress limited to S3 / RDS(5432)
#      (+ optional HTTPS for AWS APIs). No rule towards the adapter exists.
#   3. Network ACL: explicit DENY on egress TCP 8100 (SGs cannot express denies).
###############################################################################

locals {
  mt5_adapter_port = 8100
}

# --- Subnet + dedicated route table ---

resource "aws_subnet" "private_backtest" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet_private_backtest_cidr
  availability_zone = "${var.aws_region}a"

  tags = {
    Name        = "${var.project_name}-subnet-backtest-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table" "private_backtest" {
  vpc_id = aws_vpc.main.id

  # Default route via NAT: only used for AWS APIs (ECR, Secrets Manager, Logs,
  # Bedrock). S3 traffic is matched by the more specific Gateway Endpoint route.
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name        = "${var.project_name}-rt-backtest-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table_association" "backtest" {
  subnet_id      = aws_subnet.private_backtest.id
  route_table_id = aws_route_table.private_backtest.id
}

# --- S3 Gateway Endpoint (no hourly/data cost; bypasses the NAT Gateway) ---

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_backtest.id]

  tags = {
    Name        = "${var.project_name}-vpce-s3-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# --- Network ACL: explicit deny towards the MT5 Adapter port ---

resource "aws_network_acl" "private_backtest" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.private_backtest.id]

  egress {
    rule_no    = 90
    action     = "deny"
    protocol   = "tcp"
    cidr_block = "0.0.0.0/0"
    from_port  = local.mt5_adapter_port
    to_port    = local.mt5_adapter_port
  }

  egress {
    rule_no    = 100
    action     = "allow"
    protocol   = "-1"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  # NACLs are stateless: return traffic must be allowed in. Unsolicited inbound
  # is still impossible because the backtest SG has zero ingress rules.
  ingress {
    rule_no    = 100
    action     = "allow"
    protocol   = "-1"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name        = "${var.project_name}-nacl-backtest-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# --- Security Group (no ingress, minimal egress) ---

resource "aws_security_group" "backtest" {
  name        = "${var.project_name}-sg-ecs-backtest-${var.environment}"
  description = "Backtest Engine (ECS Fargate one-off) - no ingress, egress to S3 endpoint and RDS 5432 only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-sg-ecs-backtest-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_vpc_security_group_egress_rule" "backtest_to_s3" {
  security_group_id = aws_security_group.backtest.id
  description       = "HTTPS to S3 through the Gateway Endpoint (Parquet datasets, ECR image layers)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = aws_vpc_endpoint.s3.prefix_list_id
}

resource "aws_vpc_security_group_egress_rule" "backtest_to_rds" {
  security_group_id            = aws_security_group.backtest.id
  description                  = "PostgreSQL to the RDS instance (nexusquant_backtest database)"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.rds.id
}

# Fargate cannot start without HTTPS to ECR API, Secrets Manager and CloudWatch
# Logs, and the tasks need Bedrock. Without Interface VPC Endpoints these go
# through the NAT. Set backtest_allow_https_egress=false once those endpoints exist.
resource "aws_vpc_security_group_egress_rule" "backtest_https_aws_apis" {
  count = var.backtest_allow_https_egress ? 1 : 0

  security_group_id = aws_security_group.backtest.id
  description       = "HTTPS to AWS APIs via NAT (ECR, Secrets Manager, Logs, Bedrock)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}
