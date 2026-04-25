terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC Configuration
resource "aws_vpc" "vulnerable_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = "demo"
    Purpose     = "pentest-demo"
  }
}

# Public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.vulnerable_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

# Private Subnet
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.vulnerable_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${var.project_name}-private-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vulnerable_vpc.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }

  depends_on = [aws_internet_gateway.igw]
}

# NAT Gateway for private subnet internet access
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "${var.project_name}-nat"
  }

  depends_on = [aws_internet_gateway.igw]
}

# Route Table for public subnet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vulnerable_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Route Table for private subnet
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.vulnerable_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_rta" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# Web server security group - only accessible from ALB
resource "aws_security_group" "vulnerable_web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Web server security group - ALB access only"
  vpc_id      = aws_vpc.vulnerable_vpc.id

  # Allow HTTP from ALB only
  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-web-sg"
  }
}

# ALB security group - public facing
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "ALB security group"
  vpc_id      = aws_vpc.vulnerable_vpc.id

  # Allow HTTP from anywhere
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

# Database security group - restrictive for safety
resource "aws_security_group" "vulnerable_db_sg" {
  name        = "${var.project_name}-db-sg"
  description = "Database security group - only accessible from web tier"
  vpc_id      = aws_vpc.vulnerable_vpc.id

  # Only allow access from web security group
  ingress {
    description     = "MySQL from web tier only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.vulnerable_web_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}

# VULNERABLE: S3 bucket without encryption
resource "aws_s3_bucket" "vulnerable_bucket" {
  bucket = "${var.project_name}-vulnerable-data-${random_id.bucket_suffix.hex}"

  # force_destroy lets `terraform destroy` remove the bucket even if anything
  # was written to it during a pen test run.
  force_destroy = true

  tags = {
    Name        = "${var.project_name}-vulnerable-bucket"
    Environment = "demo"
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# VULNERABILITY: No encryption enabled
# VULNERABILITY: No versioning enabled
# VULNERABILITY: Public access not blocked

# VULNERABLE: RDS instance without encryption
resource "aws_db_subnet_group" "vulnerable_db_subnet" {
  name       = "${var.project_name}-db-subnet"
  subnet_ids = [aws_subnet.public_subnet.id, aws_subnet.private_subnet.id]

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

resource "aws_db_instance" "vulnerable_db" {
  identifier             = "${var.project_name}-vulnerable-db"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "vulnerableapp"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.vulnerable_db_subnet.name
  vpc_security_group_ids = [aws_security_group.vulnerable_db_sg.id]
  skip_final_snapshot    = true

  # VULNERABILITIES:
  storage_encrypted            = false # No encryption at rest
  publicly_accessible          = false  
  backup_retention_period      = 0     # No backups
  enabled_cloudwatch_logs_exports = [] # No logging

  tags = {
    Name = "${var.project_name}-vulnerable-db"
  }
}

# IAM Role for EC2 (overly permissive)
resource "aws_iam_role" "vulnerable_ec2_role" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# VULNERABILITY: Overly permissive IAM policy
resource "aws_iam_role_policy" "vulnerable_policy" {
  name = "${var.project_name}-vulnerable-policy"
  role = aws_iam_role.vulnerable_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:*",
          "rds:*",
          "ec2:*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "vulnerable_profile" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.vulnerable_ec2_role.name
}

# EC2 Instance running vulnerable web application (in private subnet for safety)
resource "aws_instance" "vulnerable_web" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_subnet.id
  vpc_security_group_ids = [aws_security_group.vulnerable_web_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.vulnerable_profile.name

  # VULNERABILITY: Unencrypted root volume
  root_block_device {
    encrypted = false
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    db_endpoint = aws_db_instance.vulnerable_db.endpoint
    db_name     = aws_db_instance.vulnerable_db.db_name
    db_username = var.db_username
    db_password = var.db_password
    bucket_name = aws_s3_bucket.vulnerable_bucket.id
  }))

  tags = {
    Name = "${var.project_name}-vulnerable-web"
  }

  depends_on = [aws_db_instance.vulnerable_db]
}

# Second public subnet in same AZ as private subnet for ALB
resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.vulnerable_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-2"
  }
}

resource "aws_route_table_association" "public_rta_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

# Application Load Balancer
resource "aws_lb" "vulnerable_alb" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_subnet.id, aws_subnet.public_subnet_2.id]

  tags = {
    Name = "${var.project_name}-alb"
  }
}

resource "aws_lb_target_group" "vulnerable_tg" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vulnerable_vpc.id

  deregistration_delay = 30

  health_check {
    path                = "/"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
}

resource "aws_lb_target_group_attachment" "vulnerable_tg_attachment" {
  target_group_arn = aws_lb_target_group.vulnerable_tg.arn
  target_id        = aws_instance.vulnerable_web.id
  port             = 80
}

resource "aws_lb_listener" "vulnerable_listener" {
  load_balancer_arn = aws_lb.vulnerable_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vulnerable_tg.arn
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
