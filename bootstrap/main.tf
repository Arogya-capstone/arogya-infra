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
output "github_actions_role_arn" { value = aws_iam_role.github_actions.arn }
output "next_step" {
  value = "Bootstrap complete. Now run terraform init + apply in environments/dev and environments/prod."
}

# ── GitHub Actions OIDC Role ──────────────────────────────────────────────────
# Kept here (not in prod Terraform) so that `terraform destroy` on prod
# never deletes the role that GitHub Actions needs to run the next apply.
variable "github_org" {
  type    = string
  default = "Arogya-capstone"
}

variable "github_infra_repo" {
  type    = string
  default = "arogya-infra"
}

variable "github_app_repo" {
  type    = string
  default = "arogya-app"
}

resource "aws_iam_role" "github_actions" {
  name = "${var.project}-prod-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:${var.github_org}/${var.github_infra_repo}:*",
            "repo:${var.github_org}/${var.github_app_repo}:*",
          ]
        }
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(local.tags, { Name = "${var.project}-prod-github-actions" })
}

resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role_policy" "github_actions_ecr" {
  name = "ecr-push"
  role = aws_iam_role.github_actions.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage", "ecr:PutImage", "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart", "ecr:CompleteLayerUpload"
        ]
        Resource = "arn:aws:ecr:${var.region}:${var.account_id}:repository/${var.project}/*"
      },
      {
        Sid      = "EKSDescribe"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = "arn:aws:eks:${var.region}:${var.account_id}:cluster/*"
      }
    ]
  })
}
