locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "terraform"
  }

  services = [
    "user-service",
    "appointment-service",
    "health-service",
    "document-service",
    "rag-service",
    "rag-worker",
  ]
}

# CloudWatch Log Groups — one per service + AIOps
resource "aws_cloudwatch_log_group" "services" {
  for_each          = toset(local.services)
  name              = "/${var.project}/${var.environment}/${each.key}"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn
  tags              = merge(local.common_tags, { Name = "${var.project}-${var.environment}-${each.key}-logs" })
}

resource "aws_cloudwatch_log_group" "lambda_notification" {
  name              = "/aws/lambda/${var.project}-${var.environment}-notification-worker"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn
  tags              = merge(local.common_tags, { Name = "${var.project}-${var.environment}-lambda-notification-logs" })
}

resource "aws_cloudwatch_log_group" "aiops" {
  name              = "/${var.project}/${var.environment}/aiops/diagnosis"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn
  tags              = merge(local.common_tags, { Name = "${var.project}-${var.environment}-aiops-logs" })
}

resource "aws_cloudwatch_log_group" "lambda_aiops" {
  name              = "/aws/lambda/${var.project}-${var.environment}-aiops-agent"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn
  tags              = merge(local.common_tags, { Name = "${var.project}-${var.environment}-lambda-aiops-logs" })
}

# SNS topic for ops alerts
resource "aws_sns_topic" "ops_alarms" {
  name              = "${var.project}-${var.environment}-ops-alarms"
  kms_master_key_id = var.kms_key_arn
  tags              = merge(local.common_tags, { Name = "${var.project}-${var.environment}-ops-alarms" })
}

resource "aws_sns_topic_subscription" "ops_email" {
  topic_arn = aws_sns_topic.ops_alarms.arn
  protocol  = "email"
  endpoint  = var.ops_email
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "rag_dlq_depth" {
  alarm_name          = "${var.project}-${var.environment}-rag-dlq-not-empty"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "RAG document processing is failing — messages in DLQ"
  alarm_actions       = [aws_sns_topic.ops_alarms.arn]
  ok_actions          = [aws_sns_topic.ops_alarms.arn]
  dimensions          = { QueueName = var.rag_processing_dlq_name }
  tags                = merge(local.common_tags, { Name = "${var.project}-${var.environment}-rag-dlq-alarm" })
}

resource "aws_cloudwatch_metric_alarm" "appointment_dlq_depth" {
  alarm_name          = "${var.project}-${var.environment}-appointment-dlq-not-empty"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Appointment notifications are failing — messages in DLQ"
  alarm_actions       = [aws_sns_topic.ops_alarms.arn]
  ok_actions          = [aws_sns_topic.ops_alarms.arn]
  dimensions          = { QueueName = var.appointment_events_dlq_name }
  tags                = merge(local.common_tags, { Name = "${var.project}-${var.environment}-appointment-dlq-alarm" })
}

# ── Lambda: notification-worker ───────────────────────────────────────────────
resource "aws_iam_role" "lambda_notification" {
  name = "${var.project}-${var.environment}-lambda-notification"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-lambda-notification" })
}

resource "aws_iam_role_policy" "lambda_notification" {
  name = "ses-sqs-logs"
  role = aws_iam_role.lambda_notification.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SQSConsume"
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = [var.appointment_events_queue_arn]
      },
      {
        Sid      = "SESSend"
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
      },
      {
        Sid      = "KMSDecrypt"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = [var.kms_key_arn]
      },
      {
        Sid      = "CloudWatchLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.lambda_notification.arn}:*"
      }
    ]
  })
}

resource "aws_lambda_function" "notification_worker" {
  filename         = "${path.module}/lambda_zips/notification_worker.zip"
  function_name    = "${var.project}-${var.environment}-notification-worker"
  role             = aws_iam_role.lambda_notification.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  source_code_hash = filebase64sha256("${path.module}/lambda_zips/notification_worker.zip")

  environment {
    variables = {
      SES_SENDER_EMAIL = var.ses_sender_email
      ENVIRONMENT      = var.environment
    }
  }

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-notification-worker" })
}

resource "aws_lambda_event_source_mapping" "notification_sqs" {
  event_source_arn = var.appointment_events_queue_arn
  function_name    = aws_lambda_function.notification_worker.arn
  batch_size       = 10
}

# ── Lambda: aiops-agent ───────────────────────────────────────────────────────
resource "aws_iam_role" "lambda_aiops" {
  name = "${var.project}-${var.environment}-lambda-aiops"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-lambda-aiops" })
}

resource "aws_iam_role_policy" "lambda_aiops" {
  name = "bedrock-cloudwatch-sns"
  role = aws_iam_role.lambda_aiops.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "CloudWatchLogsRead"
        Effect   = "Allow"
        Action   = ["logs:FilterLogEvents", "logs:GetLogEvents", "logs:DescribeLogStreams", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.region}:${var.account_id}:log-group:/${var.project}/*:*"
      },
      {
        Sid      = "BedrockInvoke"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = ["arn:aws:bedrock:${var.region}::foundation-model/amazon.nova-lite-v1:0"]
      },
      {
        Sid      = "SNSPublish"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [aws_sns_topic.ops_alarms.arn]
      },
      {
        Sid      = "KMSForSNS"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = [var.kms_key_arn]
      },
      {
        Sid      = "CloudWatchLogsWrite"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.lambda_aiops.arn}:*"
      }
    ]
  })
}

resource "aws_lambda_function" "aiops_agent" {
  filename         = "${path.module}/lambda_zips/aiops_agent.zip"
  function_name    = "${var.project}-${var.environment}-aiops-agent"
  role             = aws_iam_role.lambda_aiops.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60
  source_code_hash = filebase64sha256("${path.module}/lambda_zips/aiops_agent.zip")

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.ops_alarms.arn
      REGION        = var.region
      PROJECT       = var.project
      ENVIRONMENT   = var.environment
    }
  }

  tags = merge(local.common_tags, { Name = "${var.project}-${var.environment}-aiops-agent" })
}

# SNS → AIOps Lambda (alarm fires → AIOps diagnoses it)
resource "aws_sns_topic_subscription" "aiops_lambda" {
  topic_arn = aws_sns_topic.ops_alarms.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.aiops_agent.arn
}

resource "aws_lambda_permission" "aiops_sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.aiops_agent.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.ops_alarms.arn
}
