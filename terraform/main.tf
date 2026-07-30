provider "aws" {
  region = var.aws_region
}

# --- VPC (minimal, no NAT) ---

resource "aws_vpc" "main" {
  cidr_block           = "10.100.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.environment}-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.100.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = { Name = "${var.environment}-public" }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.100.2.0/24"
  availability_zone = "${var.aws_region}a"

  tags = { Name = "${var.environment}-private-a" }
}

# Second private subnet in a different AZ — required by RDS subnet groups
resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.100.3.0/24"
  availability_zone = "${var.aws_region}b"

  tags = { Name = "${var.environment}-private-b" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- Security Groups ---

resource "aws_security_group" "k3s_node" {
  name        = "${var.environment}-k3s-node"
  description = "aws_security_group : K3s node security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "K8s API - internal VPC access only"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name   = "${var.environment}-rds"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }
}

# --- IAM ---

resource "aws_iam_user" "admin" {
  name = var.admin_user_name
  path = "/"
}

resource "aws_iam_role" "k3s_node" {
  name = "${var.environment}-k3s-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Environment = var.environment }
}

resource "aws_iam_role_policy_attachment" "k3s_node_ssm" {
  role       = aws_iam_role.k3s_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "k3s_node" {
  name = "${var.environment}-k3s-node-profile"
  role = aws_iam_role.k3s_node.name
}
# --- RDS ---

resource "aws_db_subnet_group" "main" {
  name = "${var.environment}-db-subnet"
  # Only private subnets — RDS must never be reachable from the public subnet
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

resource "aws_db_instance" "billing" {
  identifier                  = "${var.environment}-billing-db"
  engine                      = "postgres"
  engine_version              = "16"
  instance_class              = "db.t4g.micro"
  allocated_storage           = 20
  db_name                     = "billing"
  username                    = var.db_username
  manage_master_user_password = true
  skip_final_snapshot         = true
  db_subnet_group_name        = aws_db_subnet_group.main.name
  vpc_security_group_ids      = [aws_security_group.rds.id]
  publicly_accessible         = false
  storage_encrypted           = true
}

# --- S3 ---

resource "aws_s3_bucket" "billing_exports" {
  bucket = "${var.environment}-billing-exports-assessment-${random_id.bucket.hex}"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "billing_exports_encryption" {
  bucket = aws_s3_bucket.billing_exports.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "billing_exports_public_block" {
  bucket                  = aws_s3_bucket.billing_exports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "random_id" "bucket" {
  byte_length = 4
}

# --- EC2 K3s placeholder node ---

resource "aws_instance" "k3s_node" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.medium"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.k3s_node.id]
  iam_instance_profile   = aws_iam_instance_profile.k3s_node.name

  tags = {
    Name        = "${var.environment}-k3s-node"
    Environment = var.environment
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
