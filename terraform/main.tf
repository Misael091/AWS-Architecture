terraform {
  required_version = ">= 1.5.0"
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

# ==========================================
# 1. NETWORKING (VPC, SUBNETS, NAT GATEWAY)
# ==========================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "backend-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "backend-igw" }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags                    = { Name = "public-subnet-a" }
}

resource "aws_subnet" "private_prod_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "${var.aws_region}a"
  tags              = { Name = "private-subnet-prod-a" }
}

resource "aws_subnet" "private_prod_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "${var.aws_region}b"
  tags              = { Name = "private-subnet-prod-b" }
}

resource "aws_subnet" "private_dev_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.20.0/24"
  availability_zone = "${var.aws_region}a"
  tags              = { Name = "private-subnet-dev-a" }
}

resource "aws_subnet" "private_dev_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.21.0/24"
  availability_zone = "${var.aws_region}b"
  tags              = { Name = "private-subnet-dev-b" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id
  tags          = { Name = "backend-nat-gw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table_association" "pub_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "priv_prod" {
  subnet_id      = aws_subnet.private_prod_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "priv_dev" {
  subnet_id      = aws_subnet.private_dev_a.id
  route_table_id = aws_route_table.private.id
}

# ==========================================
# 2. SECURITY GROUPS
# ==========================================

resource "aws_security_group" "ecs_sg" {
  name        = "ecs-task-sg"
  vpc_id      = aws_vpc.main.id
  description = "Allow inbound traffic to containers"

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_sg" {
  name        = "db-sg"
  vpc_id      = aws_vpc.main.id
  description = "Allow PostgreSQL traffic from ECS"

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ==========================================
# 3. S3 STORAGE WITH GLACIER ARCHIVAL
# ==========================================

resource "aws_s3_bucket" "pdf_storage" {
  bucket        = "backend-pdf-documents-private-storage"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "pdf_privacy" {
  bucket                  = aws_s3_bucket.pdf_storage.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "pdf_lifecycle" {
  bucket = aws_s3_bucket.pdf_storage.id

  rule {
    id     = "archive-to-glacier"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

# ==========================================
# 4. DATABASES (RDS POSTGRESQL ISOLATED)
# ==========================================

resource "aws_db_subnet_group" "dev" {
  name       = "dev-db-subnets"
  subnet_ids = [aws_subnet.private_dev_a.id, aws_subnet.private_dev_b.id]
}

resource "aws_db_subnet_group" "prod" {
  name       = "prod-db-subnets"
  subnet_ids = [aws_subnet.private_prod_a.id, aws_subnet.private_prod_b.id]
}

resource "aws_db_instance" "postgres_dev" {
  identifier             = "backend-db-dev"
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t4g.micro"
  db_name                = "backend_dev"
  username               = "postgres"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.dev.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  skip_final_snapshot    = true
}

resource "aws_db_instance" "postgres_prod" {
  identifier             = "backend-db-prod"
  allocated_storage      = 50
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t4g.small"
  db_name                = "backend_prod"
  username               = "postgres"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.prod.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  skip_final_snapshot    = true
}

# ==========================================
# 5. COMPUTE (ECR, ECS FARGATE & API GATEWAY)
# ==========================================

resource "aws_ecr_repository" "app" {
  name                 = "backend-service"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecs_cluster" "dev" {
  name = "cluster-dev"
}

resource "aws_ecs_cluster" "prod" {
  name = "cluster-prod"
}

resource "aws_apigatewayv2_api" "dev" {
  name          = "api-gateway-dev"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_api" "prod" {
  name          = "api-gateway-prod"
  protocol_type = "HTTP"
}

resource "aws_wafv2_web_acl" "waf" {
  name        = "backend-waf-acl"
  description = "WAF protection rules for API Gateway"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "backendWAFMetric"
    sampled_requests_enabled   = false
  }
}
