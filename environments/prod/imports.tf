# Import blocks for resources that exist in AWS from a previous partial apply
# but are not yet in Terraform state. Remove this file after a successful apply.

# ── KMS Aliases ──────────────────────────────────────────────────────────────
import {
  to = aws_kms_alias.main
  id = "alias/arogya-prod-key"
}

import {
  to = module.eks.module.eks.module.kms.aws_kms_alias.this["cluster"]
  id = "alias/eks/arogya-prod-eks"
}

# ── CloudWatch Log Groups ─────────────────────────────────────────────────────
import {
  to = module.eks.module.eks.aws_cloudwatch_log_group.this[0]
  id = "/aws/eks/arogya-prod-eks/cluster"
}

import {
  to = module.monitoring.aws_cloudwatch_log_group.services["appointment-service"]
  id = "/arogya/prod/appointment-service"
}

import {
  to = module.monitoring.aws_cloudwatch_log_group.services["rag-service"]
  id = "/arogya/prod/rag-service"
}

import {
  to = module.monitoring.aws_cloudwatch_log_group.services["user-service"]
  id = "/arogya/prod/user-service"
}

import {
  to = module.monitoring.aws_cloudwatch_log_group.services["document-service"]
  id = "/arogya/prod/document-service"
}

import {
  to = module.monitoring.aws_cloudwatch_log_group.services["rag-worker"]
  id = "/arogya/prod/rag-worker"
}

import {
  to = module.monitoring.aws_cloudwatch_log_group.services["health-service"]
  id = "/arogya/prod/health-service"
}

import {
  to = module.monitoring.aws_cloudwatch_log_group.lambda_notification
  id = "/aws/lambda/arogya-prod-notification-worker"
}

import {
  to = module.monitoring.aws_cloudwatch_log_group.aiops
  id = "/arogya/prod/aiops/diagnosis"
}

import {
  to = module.monitoring.aws_cloudwatch_log_group.lambda_aiops
  id = "/aws/lambda/arogya-prod-aiops-agent"
}

# ── Secrets Manager ───────────────────────────────────────────────────────────
import {
  to = module.security.aws_secretsmanager_secret.db_credentials
  id = "arogya/prod/db-credentials"
}

import {
  to = module.security.aws_secretsmanager_secret.jwt_private_key
  id = "arogya/prod/jwt-private-key"
}

import {
  to = module.security.aws_secretsmanager_secret.jwt_public_key
  id = "arogya/prod/jwt-public-key"
}

import {
  to = module.security.aws_secretsmanager_secret.groq_api_key
  id = "arogya/prod/groq-api-key"
}

# ── Bedrock Guardrail ─────────────────────────────────────────────────────────
import {
  to = module.security.aws_bedrock_guardrail.medical
  id = "zczbfrfz7cfz"
}

# ── SSM Parameters ────────────────────────────────────────────────────────────
import {
  to = module.security.aws_ssm_parameter.s3_bucket_name
  id = "/arogya/prod/s3-bucket-name"
}

import {
  to = module.security.aws_ssm_parameter.bedrock_llm_model_id
  id = "/arogya/prod/bedrock-llm-model-id"
}

import {
  to = module.security.aws_ssm_parameter.bedrock_embed_model_id
  id = "/arogya/prod/bedrock-embed-model-id"
}

import {
  to = module.security.aws_ssm_parameter.namespace
  id = "/arogya/prod/k8s-namespace"
}

import {
  to = module.security.aws_ssm_parameter.environment
  id = "/arogya/prod/environment"
}

# ── SQS Queues (all 4 exist in AWS but not in state) ─────────────────────────
import {
  to = module.sqs.aws_sqs_queue.rag_processing_dlq
  id = "https://sqs.us-east-1.amazonaws.com/371454942267/arogya-prod-rag-processing-dlq"
}

import {
  to = module.sqs.aws_sqs_queue.rag_processing
  id = "https://sqs.us-east-1.amazonaws.com/371454942267/arogya-prod-rag-processing"
}

import {
  to = module.sqs.aws_sqs_queue.appointment_events_dlq
  id = "https://sqs.us-east-1.amazonaws.com/371454942267/arogya-prod-appointment-events-dlq"
}

import {
  to = module.sqs.aws_sqs_queue.appointment_events
  id = "https://sqs.us-east-1.amazonaws.com/371454942267/arogya-prod-appointment-events"
}

# ── ECR Repositories ──────────────────────────────────────────────────────────
import {
  to = module.ecr.aws_ecr_repository.services["appointment-service"]
  id = "arogya/appointment-service"
}

import {
  to = module.ecr.aws_ecr_repository.services["rag-worker"]
  id = "arogya/rag-worker"
}

import {
  to = module.ecr.aws_ecr_repository.services["rag-service"]
  id = "arogya/rag-service"
}

import {
  to = module.ecr.aws_ecr_repository.services["document-service"]
  id = "arogya/document-service"
}

import {
  to = module.ecr.aws_ecr_repository.services["health-service"]
  id = "arogya/health-service"
}

import {
  to = module.ecr.aws_ecr_repository.services["frontend"]
  id = "arogya/frontend"
}

import {
  to = module.ecr.aws_ecr_repository.services["user-service"]
  id = "arogya/user-service"
}

# ── IAM Roles ─────────────────────────────────────────────────────────────────
import {
  to = module.irsa.aws_iam_role.github_actions
  id = "arogya-prod-github-actions"
}

import {
  to = module.monitoring.aws_iam_role.lambda_notification
  id = "arogya-prod-lambda-notification"
}

import {
  to = module.monitoring.aws_iam_role.lambda_aiops
  id = "arogya-prod-lambda-aiops"
}

# ── RDS Subnet Group ──────────────────────────────────────────────────────────
import {
  to = module.rds.aws_db_subnet_group.rds
  id = "arogya-prod-db-subnet-group"
}

# ── Remove OIDC provider resource from state (switched to data source) ────────
removed {
  from = module.irsa.aws_iam_openid_connect_provider.github
  lifecycle {
    destroy = false
  }
}
