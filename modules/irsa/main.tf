locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "terraform"
  }

  # Secrets Manager — sensitive values only
  common_secret_arns = [
    var.db_credentials_secret_arn,
    var.jwt_private_key_secret_arn,
    var.jwt_public_key_secret_arn,
    var.groq_api_key_secret_arn,
  ]
}

# Reusable OIDC trust policy factory
data "aws_iam_policy_document" "trust" {
  for_each = {
    user-service        = "sa-user-service"
    appointment-service = "sa-appointment-service"
    health-service      = "sa-health-service"
    document-service    = "sa-document-service"
    rag-service         = "sa-rag-service"
    rag-worker          = "sa-rag-worker"
    keda                = "keda-operator"
  }

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider}:sub"
      values   = ["system:serviceaccount:${each.key == "keda" ? "keda" : var.namespace}:${each.value}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# Common policy — Secrets Manager (sensitive) + SSM (config) + CloudWatch + KMS
data "aws_iam_policy_document" "common" {
  statement {
    sid       = "SecretsManager"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = local.common_secret_arns
  }
  statement {
    sid       = "SSMParameterStore"
    effect    = "Allow"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = ["arn:aws:ssm:${var.region}:${var.account_id}:parameter${var.ssm_parameter_prefix}/*"]
  }
  statement {
    sid       = "CloudWatchLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["arn:aws:logs:${var.region}:${var.account_id}:log-group:/${var.project}/*"]
  }
  statement {
    sid       = "KMSDecrypt"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey"]
    resources = [var.kms_key_arn]
  }
}

# ── user-service ──────────────────────────────────────────────────────────────
resource "aws_iam_role" "user_service" {
  name               = "${var.project}-${var.environment}-sa-user-service"
  assume_role_policy = data.aws_iam_policy_document.trust["user-service"].json
  tags               = merge(local.common_tags, { Name = "${var.project}-${var.environment}-sa-user-service" })
}
resource "aws_iam_role_policy" "user_service_common" {
  name   = "common"
  role   = aws_iam_role.user_service.id
  policy = data.aws_iam_policy_document.common.json
}

# ── appointment-service ───────────────────────────────────────────────────────
resource "aws_iam_role" "appointment_service" {
  name               = "${var.project}-${var.environment}-sa-appointment-service"
  assume_role_policy = data.aws_iam_policy_document.trust["appointment-service"].json
  tags               = merge(local.common_tags, { Name = "${var.project}-${var.environment}-sa-appointment-service" })
}
resource "aws_iam_role_policy" "appointment_service_common" {
  name   = "common"
  role   = aws_iam_role.appointment_service.id
  policy = data.aws_iam_policy_document.common.json
}
resource "aws_iam_role_policy" "appointment_service_sqs" {
  name = "sqs-send"
  role = aws_iam_role.appointment_service.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SQSSend"
      Effect   = "Allow"
      Action   = ["sqs:SendMessage", "sqs:GetQueueUrl"]
      Resource = [var.appointment_events_queue_arn, var.rag_processing_queue_arn]
    }]
  })
}

# ── health-service ────────────────────────────────────────────────────────────
resource "aws_iam_role" "health_service" {
  name               = "${var.project}-${var.environment}-sa-health-service"
  assume_role_policy = data.aws_iam_policy_document.trust["health-service"].json
  tags               = merge(local.common_tags, { Name = "${var.project}-${var.environment}-sa-health-service" })
}
resource "aws_iam_role_policy" "health_service_common" {
  name   = "common"
  role   = aws_iam_role.health_service.id
  policy = data.aws_iam_policy_document.common.json
}

# ── document-service ──────────────────────────────────────────────────────────
resource "aws_iam_role" "document_service" {
  name               = "${var.project}-${var.environment}-sa-document-service"
  assume_role_policy = data.aws_iam_policy_document.trust["document-service"].json
  tags               = merge(local.common_tags, { Name = "${var.project}-${var.environment}-sa-document-service" })
}
resource "aws_iam_role_policy" "document_service_common" {
  name   = "common"
  role   = aws_iam_role.document_service.id
  policy = data.aws_iam_policy_document.common.json
}
resource "aws_iam_role_policy" "document_service_s3" {
  name = "s3-documents"
  role = aws_iam_role.document_service.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3Objects"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = "${var.documents_bucket_arn}/*"
      },
      {
        Sid      = "S3List"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.documents_bucket_arn
      }
    ]
  })
}
resource "aws_iam_role_policy" "document_service_sqs" {
  name = "sqs-rag-send"
  role = aws_iam_role.document_service.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SQSSend"
      Effect   = "Allow"
      Action   = ["sqs:SendMessage", "sqs:GetQueueUrl"]
      Resource = [var.rag_processing_queue_arn]
    }]
  })
}

# ── rag-service ───────────────────────────────────────────────────────────────
resource "aws_iam_role" "rag_service" {
  name               = "${var.project}-${var.environment}-sa-rag-service"
  assume_role_policy = data.aws_iam_policy_document.trust["rag-service"].json
  tags               = merge(local.common_tags, { Name = "${var.project}-${var.environment}-sa-rag-service" })
}
resource "aws_iam_role_policy" "rag_service_common" {
  name   = "common"
  role   = aws_iam_role.rag_service.id
  policy = data.aws_iam_policy_document.common.json
}
resource "aws_iam_role_policy" "rag_service_bedrock" {
  name = "bedrock-invoke"
  role = aws_iam_role.rag_service.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "BedrockInvoke"
      Effect = "Allow"
      Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream", "bedrock:ApplyGuardrail"]
      Resource = [
        "arn:aws:bedrock:${var.region}::foundation-model/amazon.nova-lite-v1:0",
        "arn:aws:bedrock:${var.region}::foundation-model/amazon.titan-embed-text-v2:0",
        "arn:aws:bedrock:${var.region}:${var.account_id}:guardrail/*",
      ]
    }]
  })
}

# ── rag-worker ────────────────────────────────────────────────────────────────
resource "aws_iam_role" "rag_worker" {
  name               = "${var.project}-${var.environment}-sa-rag-worker"
  assume_role_policy = data.aws_iam_policy_document.trust["rag-worker"].json
  tags               = merge(local.common_tags, { Name = "${var.project}-${var.environment}-sa-rag-worker" })
}
resource "aws_iam_role_policy" "rag_worker_common" {
  name   = "common"
  role   = aws_iam_role.rag_worker.id
  policy = data.aws_iam_policy_document.common.json
}
resource "aws_iam_role_policy" "rag_worker_sqs" {
  name = "sqs-consume"
  role = aws_iam_role.rag_worker.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SQSConsume"
      Effect   = "Allow"
      Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
      Resource = [var.rag_processing_queue_arn, var.rag_processing_dlq_arn]
    }]
  })
}
resource "aws_iam_role_policy" "rag_worker_textract" {
  name = "textract"
  role = aws_iam_role.rag_worker.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "TextractSync"
        Effect   = "Allow"
        Action   = ["textract:DetectDocumentText", "textract:AnalyzeDocument", "textract:StartDocumentTextDetection", "textract:GetDocumentTextDetection"]
        Resource = "*"
      },
      {
        Sid      = "S3ForTextract"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${var.documents_bucket_arn}/*"
      }
    ]
  })
}
resource "aws_iam_role_policy" "rag_worker_bedrock" {
  name = "bedrock-embeddings"
  role = aws_iam_role.rag_worker.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "BedrockEmbeddings"
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel"]
      Resource = ["arn:aws:bedrock:${var.region}::foundation-model/amazon.titan-embed-text-v2:0"]
    }]
  })
}

# ── KEDA operator ─────────────────────────────────────────────────────────────
resource "aws_iam_role" "keda" {
  name               = "${var.project}-${var.environment}-sa-keda"
  assume_role_policy = data.aws_iam_policy_document.trust["keda"].json
  tags               = merge(local.common_tags, { Name = "${var.project}-${var.environment}-sa-keda" })
}
resource "aws_iam_role_policy" "keda_sqs" {
  name = "sqs-metrics"
  role = aws_iam_role.keda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SQSMetrics"
      Effect   = "Allow"
      Action   = ["sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
      Resource = [var.rag_processing_queue_arn]
    }]
  })
}

# ── GitHub OIDC (for GitHub Actions — no long-lived AWS keys) ─────────────────
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  tags            = merge(local.common_tags, { Name = "${var.project}-${var.environment}-github-oidc" })
}

resource "aws_iam_role" "github_actions" {
  name = "${var.project}-${var.environment}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
        }
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-github-actions" })
}

resource "aws_iam_role_policy" "github_actions" {
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
        Sid      = "ECRPush"
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload"]
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
