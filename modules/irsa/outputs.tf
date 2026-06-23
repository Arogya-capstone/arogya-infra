output "user_service_role_arn" { value = aws_iam_role.user_service.arn }
output "appointment_service_role_arn" { value = aws_iam_role.appointment_service.arn }
output "health_service_role_arn" { value = aws_iam_role.health_service.arn }
output "document_service_role_arn" { value = aws_iam_role.document_service.arn }
output "rag_service_role_arn" { value = aws_iam_role.rag_service.arn }
output "rag_worker_role_arn" { value = aws_iam_role.rag_worker.arn }
output "keda_role_arn" { value = aws_iam_role.keda.arn }
output "github_actions_role_arn" { value = aws_iam_role.github_actions.arn }
