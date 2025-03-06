# terraform/modules/monitoring/main.tf

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
