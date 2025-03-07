output "chat_history_table_name" {
  value = aws_dynamodb_table.chat_history.name
}

output "dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}

output "frontend_bucket_id" {
  value = aws_s3_bucket.frontend.id
}

output "frontend_bucket_arn" {
  value = aws_s3_bucket.frontend.arn
}

output "frontend_bucket_regional_domain_name" {
  value = aws_s3_bucket.frontend.bucket_regional_domain_name
}