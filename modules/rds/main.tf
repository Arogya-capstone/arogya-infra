locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "terraform"
  }
}

resource "random_password" "db_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_db_subnet_group" "rds" {
  name       = "${var.project}-${var.environment}-db-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = merge(local.common_tags, { Name = "${var.project}-${var.environment}-db-subnet-group" })
}

resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.environment}-rds-sg"
  description = "RDS PostgreSQL - allow only from EKS nodes"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_node_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-rds-sg" })
}

resource "aws_db_instance" "postgres" {
  identifier              = "${var.project}-${var.environment}-db"
  engine                  = "postgres"
  engine_version          = var.engine_version
  instance_class          = var.instance_class
  allocated_storage       = var.allocated_storage
  max_allocated_storage   = 100
  db_name                 = "arogya"
  username                = "dbadmin"
  password                = random_password.db_password.result
  db_subnet_group_name    = aws_db_subnet_group.rds.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  multi_az                = var.multi_az
  storage_encrypted       = true
  kms_key_id              = var.kms_key_arn
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"
  skip_final_snapshot     = true

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-postgres" })
}
