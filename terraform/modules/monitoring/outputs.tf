# terraform/modules/monitoring/outputs.tf
output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}
