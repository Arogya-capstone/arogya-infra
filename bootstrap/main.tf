# Bootstrap — run this ONCE before anything else.
# Creates the S3 bucket and DynamoDB table that all environments use as remote backend.
# Uses local state intentionally (no backend block here).
#
# Usage:
#   cd arogya-infra/bootstrap
#   terraform init
#   terraform apply -var="account_id=371454942267"

terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.region
}

variable "account_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "arogya"
}

locals {
  bucket_name = "${var.project}-tf-state-${var.account_id}"
  table_name  = "${var.project}-tf-locks"
  tags = {
    Project     = var.project
    Environment = "bootstrap"
    Owner       = "arogya-team"
    ManagedBy   = "terraform"
  }
}

# S3 bucket for remote state
resource "aws_s3_bucket" "tf_state" {
  bucket        = local.bucket_name
  force_destroy = false
  tags          = merge(local.tags, { Name = local.bucket_name })
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for state locking
resource "aws_dynamodb_table" "tf_locks" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge(local.tags, { Name = local.table_name })
}

output "state_bucket" { value = aws_s3_bucket.tf_state.id }
output "lock_table" { value = aws_dynamodb_table.tf_locks.name }
output "next_step" {
  value = "Bootstrap complete. Now run terraform init + apply in environments/dev and environments/prod."
}
