output "ops_alarms_topic_arn" { value = aws_sns_topic.ops_alarms.arn }
output "lambda_notification_role_arn" { value = aws_iam_role.lambda_notification.arn }
output "lambda_notification_arn" { value = aws_lambda_function.notification_worker.arn }
output "lambda_aiops_arn" { value = aws_lambda_function.aiops_agent.arn }
