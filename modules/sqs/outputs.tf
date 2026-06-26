output "rag_processing_queue_url" { value = aws_sqs_queue.rag_processing.url }
output "rag_processing_queue_arn" { value = aws_sqs_queue.rag_processing.arn }
output "rag_processing_dlq_arn" { value = aws_sqs_queue.rag_processing_dlq.arn }
output "appointment_events_queue_url" { value = aws_sqs_queue.appointment_events.url }
output "appointment_events_queue_id" { value = aws_sqs_queue.appointment_events.id }
output "appointment_events_queue_arn" { value = aws_sqs_queue.appointment_events.arn }
output "appointment_events_dlq_arn" { value = aws_sqs_queue.appointment_events_dlq.arn }
