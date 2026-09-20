###############################################################################
# Module: networking — main.tf
# VPC, Subnets, Internet Gateway, NAT Gateway, Route Tables, Security Groups
###############################################################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project_name}-vpc-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# --- Subnets ---

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_public_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-subnet-public-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_windows" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet_private_windows_cidr
  availability_zone = "${var.aws_region}a"

  tags = {
    Name        = "${var.project_name}-subnet-windows-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_linux" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet_private_linux_cidr
  availability_zone = "${var.aws_region}a"

  tags = {
    Name        = "${var.project_name}-subnet-linux-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_db_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet_private_db_a_cidr
  availability_zone = "${var.aws_region}a"

  tags = {
    Name        = "${var.project_name}-subnet-db-a-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_subnet" "private_db_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.subnet_private_db_b_cidr
  availability_zone = "${var.aws_region}b"

  tags = {
    Name        = "${var.project_name}-subnet-db-b-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# --- NAT Gateway (for private subnets outbound access) ---

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name        = "${var.project_name}-nat-eip-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name        = "${var.project_name}-nat-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }

  depends_on = [aws_internet_gateway.igw]
}

# --- Route Tables ---

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "${var.project_name}-rt-public-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name        = "${var.project_name}-rt-private-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_route_table_association" "windows" {
  subnet_id      = aws_subnet.private_windows.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "linux" {
  subnet_id      = aws_subnet.private_linux.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "db_a" {
  subnet_id      = aws_subnet.private_db_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "db_b" {
  subnet_id      = aws_subnet.private_db_b.id
  route_table_id = aws_route_table.private.id
}

# --- Security Groups ---

resource "aws_security_group" "windows_adapter" {
  name        = "${var.project_name}-sg-windows-adapter-${var.environment}"
  description = "MT5 Adapter: REST from Linux subnet, optional RDP from admin CIDR"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "MT5 REST API from Linux backend subnet"
    from_port   = 8100
    to_port     = 8100
    protocol    = "tcp"
    cidr_blocks = [var.subnet_private_linux_cidr]
  }

  dynamic "ingress" {
    for_each = var.rdp_admin_cidr != "" ? [1] : []
    content {
      description = "RDP for initial MT5 terminal setup"
      from_port   = 3389
      to_port     = 3389
      protocol    = "tcp"
      cidr_blocks = [var.rdp_admin_cidr]
    }
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-sg-windows-adapter-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-sg-rds-${var.environment}"
  description = "RDS PostgreSQL: connections from Windows adapter and Linux subnet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from Windows adapter"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.windows_adapter.id]
  }

  ingress {
    description = "PostgreSQL from Linux backend subnet"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.subnet_private_linux_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-sg-rds-${var.environment}"
    Environment = var.environment
    Project     = var.project_name
  }
}
