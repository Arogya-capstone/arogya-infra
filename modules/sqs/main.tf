locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "terraform"
  }
}

# RAG processing queue (document-service → rag-worker via KEDA)
resource "aws_sqs_queue" "rag_processing_dlq" {
  name                      = "${var.project}-${var.environment}-rag-processing-dlq"
  kms_master_key_id         = var.kms_key_arn
  message_retention_seconds = 1209600
  tags                      = merge(local.common_tags, { Name = "${var.project}-${var.environment}-rag-dlq" })
}

resource "aws_sqs_queue" "rag_processing" {
  name                       = "${var.project}-${var.environment}-rag-processing"
  kms_master_key_id          = var.kms_key_arn
  visibility_timeout_seconds = 300

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.rag_processing_dlq.arn
    maxReceiveCount     = 3
  })

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-rag-processing" })
}

# Appointment events queue (appointment-service → Lambda notification-worker)
resource "aws_sqs_queue" "appointment_events_dlq" {
  name                      = "${var.project}-${var.environment}-appointment-events-dlq"
  kms_master_key_id         = var.kms_key_arn
  message_retention_seconds = 1209600
  tags                      = merge(local.common_tags, { Name = "${var.project}-${var.environment}-appointment-dlq" })
}

resource "aws_sqs_queue" "appointment_events" {
  name                       = "${var.project}-${var.environment}-appointment-events"
  kms_master_key_id          = var.kms_key_arn
  visibility_timeout_seconds = 60

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.appointment_events_dlq.arn
    maxReceiveCount     = 3
  })

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-appointment-events" })
}

data "aws_iam_policy_document" "sqs_lambda_policy" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.appointment_events.arn]
    principals {
      type        = "AWS"
      identifiers = [var.lambda_role_arn]
    }
  }
}

resource "aws_sqs_queue_policy" "lambda_policy" {
  queue_url = aws_sqs_queue.appointment_events.id
  policy    = data.aws_iam_policy_document.sqs_lambda_policy.json
}
