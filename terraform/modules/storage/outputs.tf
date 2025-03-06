# terraform/modules/storage/outputs.tf
output "chat_history_table_name" {
  value = aws_dynamodb_table.chat_history.name
}

output "dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}
