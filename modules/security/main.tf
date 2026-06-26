locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "terraform"
  }
  ssm_prefix = "/${var.project}/${var.environment}"
}

# Secrets Manager
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project}/${var.environment}/db-credentials"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 7
  tags                    = merge(local.common_tags, { Name = "${var.project}-${var.environment}-db-credentials" })
}

resource "aws_secretsmanager_secret" "jwt_private_key" {
  name                    = "${var.project}/${var.environment}/jwt-private-key"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 7
  tags                    = merge(local.common_tags, { Name = "${var.project}-${var.environment}-jwt-private-key" })
}

resource "aws_secretsmanager_secret_version" "jwt_private_key" {
  secret_id     = aws_secretsmanager_secret.jwt_private_key.id
  secret_string = var.jwt_private_key
}

resource "aws_secretsmanager_secret" "jwt_public_key" {
  name                    = "${var.project}/${var.environment}/jwt-public-key"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 7
  tags                    = merge(local.common_tags, { Name = "${var.project}-${var.environment}-jwt-public-key" })
}

resource "aws_secretsmanager_secret_version" "jwt_public_key" {
  secret_id     = aws_secretsmanager_secret.jwt_public_key.id
  secret_string = var.jwt_public_key
}

resource "aws_secretsmanager_secret" "groq_api_key" {
  name                    = "${var.project}/${var.environment}/groq-api-key"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 7
  tags                    = merge(local.common_tags, { Name = "${var.project}-${var.environment}-groq-api-key" })
}

resource "aws_secretsmanager_secret_version" "groq_api_key" {
  secret_id     = aws_secretsmanager_secret.groq_api_key.id
  secret_string = var.groq_api_key
}

# SES identity
resource "aws_ses_email_identity" "sender" {
  email = var.ses_sender_email
}

# CloudTrail
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${var.project}-${var.environment}-cloudtrail-${var.account_id}"
  force_destroy = true
  tags          = merge(local.common_tags, { Name = "${var.project}-${var.environment}-cloudtrail" })
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${var.account_id}/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      }
    ]
  })
}

resource "aws_cloudtrail" "main" {
  name                          = "${var.project}-${var.environment}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  kms_key_id                    = var.kms_key_arn
  tags                          = merge(local.common_tags, { Name = "${var.project}-${var.environment}-trail" })
}

# Documents S3 bucket
resource "aws_s3_bucket" "documents" {
  bucket        = "${var.project}-${var.environment}-documents-${var.account_id}"
  force_destroy = false
  tags          = merge(local.common_tags, { Name = "${var.project}-${var.environment}-documents" })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket                  = aws_s3_bucket.documents.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── Bedrock Guardrail — content safety for medical chatbot ────────────────────
resource "aws_bedrock_guardrail" "medical" {
  name                      = "${var.project}-${var.environment}-medical-guardrail"
  description               = "Blocks off-topic, harmful, and PII content from the Arogya AI chatbot"
  blocked_input_messaging   = "I can only help with health and medical questions. Please rephrase your query."
  blocked_outputs_messaging = "The response was blocked for safety reasons. Please consult a qualified doctor."

  topic_policy_config {
    topics_config {
      name       = "non-medical-topics"
      definition = "Any topic not related to health, medical symptoms, medications, or wellness"
      examples   = ["Tell me a joke", "What stocks should I buy", "Write code for me"]
      type       = "DENY"
    }
  }

  sensitive_information_policy_config {
    pii_entities_config {
      type   = "CREDIT_DEBIT_CARD_NUMBER"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "AWS_ACCESS_KEY"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "PASSWORD"
      action = "ANONYMIZE"
    }
  }

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-guardrail" })
}

resource "aws_bedrock_guardrail_version" "medical" {
  guardrail_arn = aws_bedrock_guardrail.medical.guardrail_arn
  description   = "Active version for ${var.environment}"
}

# ── SSM Parameters (non-cross-module values only) ─────────────────────────────
resource "aws_ssm_parameter" "s3_bucket_name" {
  name  = "${local.ssm_prefix}/s3-bucket-name"
  type  = "String"
  value = aws_s3_bucket.documents.id
  tags  = merge(local.common_tags, { Name = "s3-bucket-name" })
}

resource "aws_ssm_parameter" "bedrock_guardrail_id" {
  name  = "${local.ssm_prefix}/bedrock-guardrail-id"
  type  = "String"
  value = aws_bedrock_guardrail.medical.guardrail_id
  tags  = merge(local.common_tags, { Name = "bedrock-guardrail-id" })
}

resource "aws_ssm_parameter" "bedrock_guardrail_version" {
  name  = "${local.ssm_prefix}/bedrock-guardrail-version"
  type  = "String"
  value = aws_bedrock_guardrail_version.medical.version
  tags  = merge(local.common_tags, { Name = "bedrock-guardrail-version" })
}

resource "aws_ssm_parameter" "bedrock_llm_model_id" {
  name  = "${local.ssm_prefix}/bedrock-llm-model-id"
  type  = "String"
  value = "amazon.nova-lite-v1:0"
  tags  = merge(local.common_tags, { Name = "bedrock-llm-model-id" })
}

resource "aws_ssm_parameter" "bedrock_embed_model_id" {
  name  = "${local.ssm_prefix}/bedrock-embed-model-id"
  type  = "String"
  value = "amazon.titan-embed-text-v2:0"
  tags  = merge(local.common_tags, { Name = "bedrock-embed-model-id" })
}

resource "aws_ssm_parameter" "namespace" {
  name  = "${local.ssm_prefix}/k8s-namespace"
  type  = "String"
  value = var.namespace
  tags  = merge(local.common_tags, { Name = "k8s-namespace" })
}

resource "aws_ssm_parameter" "environment" {
  name  = "${local.ssm_prefix}/environment"
  type  = "String"
  value = var.environment
  tags  = merge(local.common_tags, { Name = "environment" })
}
