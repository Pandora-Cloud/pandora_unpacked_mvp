
resource "aws_kms_key" "chat_key" {
  description = "Key for chatbot data encryption"
}

resource "aws_wafv2_web_acl" "api_protection" {
  name  = "${var.project_name}-web-acl"
  scope = "REGIONAL"
  default_action {
    allow {}
  }
  rule {
    name     = "rate-limit"
    priority = 1
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 1000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
    }
  }
}

resource "aws_wafv2_web_acl_association" "api" {
  resource_arn = var.api_arn
  web_acl_arn  = aws_wafv2_web_acl.api_protection.arn
}