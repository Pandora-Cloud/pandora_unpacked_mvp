#!/bin/bash

# Ensure script runs from its own directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || { echo "Failed to change to script directory"; exit 1; }

# Create root directories with error checking
for dir in terraform/modules/{auth,compute,iam,monitoring,networking,security,storage} lambda src/components src/public; do
  mkdir -p "$dir" || { echo "Failed to create directory $dir"; exit 1; }
done

# Terraform Files

cat << 'EOF' > terraform/provider.tf || { echo "Failed to create terraform/provider.tf"; exit 1; }
# terraform/provider.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40.0"
    }
  }
  
  required_version = ">= 1.0"
  
  backend "s3" {
    bucket         = "chatbot-mvp-terraform-state"
    key            = "production/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "chatbot-mvp-terraform-state-lock"
    profile        = "forge_interns_tf"
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile
}
EOF

cat << 'EOF' > terraform/variables.tf || { echo "Failed to create terraform/variables.tf"; exit 1; }
# terraform/variables.tf
variable "region" {
  default = "us-west-2"
}

variable "profile" {
  default = "forge_interns_tf"
}

variable "project_name" {
  default = "chatbot-mvp"
}
EOF

cat << 'EOF' > terraform/main.tf || { echo "Failed to create terraform/main.tf"; exit 1; }
# terraform/main.tf
module "auth" {
  source       = "./modules/auth"
  project_name = var.project_name
}

module "compute" {
  source           = "./modules/compute"
  project_name     = var.project_name
  lambda_role_arn  = module.iam.lambda_exec_arn
  dynamodb_table   = module.storage.chat_history_table_name
  dlq_arn          = module.storage.dlq_arn
}

module "iam" {
  source         = "./modules/iam"
  project_name   = var.project_name
  region         = var.region
  dynamodb_table = module.storage.chat_history_table_name
  dlq_arn        = module.storage.dlq_arn
}

module "monitoring" {
  source       = "./modules/monitoring"
  project_name = var.project_name
}

module "networking" {
  source = "./modules/networking"
}

module "security" {
  source       = "./modules/security"
  project_name = var.project_name
  api_arn      = module.compute.api_arn
}

module "storage" {
  source           = "./modules/storage"
  project_name     = var.project_name
  kms_key_arn      = module.security.kms_key_arn
}
EOF

cat << 'EOF' > terraform/modules/auth/main.tf || { echo "Failed to create terraform/modules/auth/main.tf"; exit 1; }
# terraform/modules/auth/main.tf
variable "project_name" {
  type = string
}

resource "aws_cognito_user_pool" "chat_pool" {
  name = "${var.project_name}-UserPool"
  
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  
  password_policy {
    minimum_length    = 8
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }
  
  admin_create_user_config {
    allow_admin_create_user_only = false
  }
  
  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }
}

resource "aws_cognito_user_pool_client" "client" {
  name                                 = "${var.project_name}-Client"
  user_pool_id                         = aws_cognito_user_pool.chat_pool.id
  explicit_auth_flows                  = ["USER_PASSWORD_AUTH", "ADMIN_NO_SRP_AUTH"]
  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  callback_urls                        = ["https://chat.pandoracloud.net/callback"]
  logout_urls                          = ["https://chat.pandoracloud.net/logout"]
}

resource "aws_cognito_identity_pool" "chat_identity_pool" {
  identity_pool_name               = "${var.project_name}-IdentityPool"
  allow_unauthenticated_identities = false
  cognito_user_pools {
    user_pool_id = aws_cognito_user_pool.chat_pool.id
    client_id    = aws_cognito_user_pool_client.client.id
    provider_name = "cognito-idp.us-west-2.amazonaws.com/${aws_cognito_user_pool.chat_pool.id}"
  }
}

resource "aws_ssm_parameter" "user_pool_id" {
  name  = "/${var.project_name}/cognito-user-pool-id"
  type  = "SecureString"
  value = aws_cognito_user_pool.chat_pool.id
}

resource "aws_ssm_parameter" "client_id" {
  name  = "/${var.project_name}/cognito-client-id"
  type  = "SecureString"
  value = aws_cognito_user_pool_client.client.id
}

resource "aws_ssm_parameter" "identity_pool_id" {
  name  = "/${var.project_name}/cognito-identity-pool-id"
  type  = "SecureString"
  value = aws_cognito_identity_pool.chat_identity_pool.id
}
EOF

cat << 'EOF' > terraform/modules/auth/outputs.tf || { echo "Failed to create terraform/modules/auth/outputs.tf"; exit 1; }
# terraform/modules/auth/outputs.tf
output "user_pool_arn" {
  value = aws_cognito_user_pool.chat_pool.arn
}

output "identity_pool_id" {
  value = aws_cognito_identity_pool.chat_identity_pool.id
}
EOF

cat << 'EOF' > terraform/modules/compute/main.tf || { echo "Failed to create terraform/modules/compute/main.tf"; exit 1; }
# terraform/modules/compute/main.tf
variable "project_name" {
  type = string
}

variable "lambda_role_arn" {
  type = string
}

variable "dynamodb_table" {
  type = string
}

variable "dlq_arn" {
  type = string
}

resource "aws_lambda_function" "chat_processor" {
  filename      = "lambda/chat_processor.zip"
  function_name = "${var.project_name}-chatProcessor"
  role          = var.lambda_role_arn
  handler       = "chat_processor.handler"
  runtime       = "python3.11"
  tracing_config {
    mode = "Active"
  }
  dead_letter_config {
    target_arn = var.dlq_arn
  }
  environment {
    variables = {
      DYNAMODB_TABLE = var.dynamodb_table
      SSM_PREFIX     = "/${var.project_name}"
    }
  }
}

resource "aws_lambda_function" "auth_handler" {
  filename      = "lambda/auth_handler.zip"
  function_name = "${var.project_name}-authHandler"
  role          = var.lambda_role_arn
  handler       = "auth_handler.handler"
  runtime       = "python3.11"
  tracing_config {
    mode = "Active"
  }
  dead_letter_config {
    target_arn = var.dlq_arn
  }
  environment {
    variables = {
      SSM_PREFIX = "/${var.project_name}"
    }
  }
}

resource "aws_lambda_function" "history_manager" {
  filename      = "lambda/history_manager.zip"
  function_name = "${var.project_name}-historyManager"
  role          = var.lambda_role_arn
  handler       = "history_manager.handler"
  runtime       = "python3.11"
  tracing_config {
    mode = "Active"
  }
  dead_letter_config {
    target_arn = var.dlq_arn
  }
  environment {
    variables = {
      DYNAMODB_TABLE = var.dynamodb_table
      SSM_PREFIX     = "/${var.project_name}"
    }
  }
}

resource "aws_api_gateway_rest_api" "chat_api" {
  name = "${var.project_name}-ChatAPI"
}

# Auth Resource
resource "aws_api_gateway_resource" "auth" {
  rest_api_id = aws_api_gateway_rest_api.chat_api.id
  parent_id   = aws_api_gateway_rest_api.chat_api.root_resource_id
  path_part   = "auth"
}

resource "aws_api_gateway_method" "auth_post" {
  rest_api_id   = aws_api_gateway_rest_api.chat_api.id
  resource_id   = aws_api_gateway_resource.auth.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "auth_integration" {
  rest_api_id             = aws_api_gateway_rest_api.chat_api.id
  resource_id             = aws_api_gateway_resource.auth.id
  http_method             = aws_api_gateway_method.auth_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.auth_handler.invoke_arn
}

# Chat Resource
resource "aws_api_gateway_resource" "chat" {
  rest_api_id = aws_api_gateway_rest_api.chat_api.id
  parent_id   = aws_api_gateway_rest_api.chat_api.root_resource_id
  path_part   = "chat"
}

resource "aws_api_gateway_resource" "chat_session" {
  rest_api_id = aws_api_gateway_rest_api.chat_api.id
  parent_id   = aws_api_gateway_resource.chat.id
  path_part   = "{sessionId}"
}

resource "aws_api_gateway_method" "chat_post" {
  rest_api_id   = aws_api_gateway_rest_api.chat_api.id
  resource_id   = aws_api_gateway_resource.chat_session.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "chat_integration" {
  rest_api_id             = aws_api_gateway_rest_api.chat_api.id
  resource_id             = aws_api_gateway_resource.chat_session.id
  http_method             = aws_api_gateway_method.chat_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.chat_processor.invoke_arn
}

# History Resource
resource "aws_api_gateway_resource" "history" {
  rest_api_id = aws_api_gateway_rest_api.chat_api.id
  parent_id   = aws_api_gateway_rest_api.chat_api.root_resource_id
  path_part   = "history"
}

resource "aws_api_gateway_method" "history_get" {
  rest_api_id   = aws_api_gateway_rest_api.chat_api.id
  resource_id   = aws_api_gateway_resource.history.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "history_integration" {
  rest_api_id             = aws_api_gateway_rest_api.chat_api.id
  resource_id             = aws_api_gateway_resource.history.id
  http_method             = aws_api_gateway_method.history_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.history_manager.invoke_arn
}

# CORS for all methods
resource "aws_api_gateway_method" "options" {
  for_each      = {
    "auth"    = aws_api_gateway_resource.auth.id,
    "chat"    = aws_api_gateway_resource.chat_session.id,
    "history" = aws_api_gateway_resource.history.id
  }
  rest_api_id   = aws_api_gateway_rest_api.chat_api.id
  resource_id   = each.value
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_integration" {
  for_each      = {
    "auth"    = aws_api_gateway_resource.auth.id,
    "chat"    = aws_api_gateway_resource.chat_session.id,
    "history" = aws_api_gateway_resource.history.id
  }
  rest_api_id             = aws_api_gateway_rest_api.chat_api.id
  resource_id             = each.value
  http_method             = "OPTIONS"
  type                    = "MOCK"
  request_templates       = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "options_response" {
  for_each      = {
    "auth"    = aws_api_gateway_resource.auth.id,
    "chat"    = aws_api_gateway_resource.chat_session.id,
    "history" = aws_api_gateway_resource.history.id
  }
  rest_api_id   = aws_api_gateway_rest_api.chat_api.id
  resource_id   = each.value
  http_method   = "OPTIONS"
  status_code   = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  for_each      = {
    "auth"    = aws_api_gateway_resource.auth.id,
    "chat"    = aws_api_gateway_resource.chat_session.id,
    "history" = aws_api_gateway_resource.history.id
  }
  rest_api_id   = aws_api_gateway_rest_api.chat_api.id
  resource_id   = each.value
  http_method   = "OPTIONS"
  status_code   = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,POST,GET'"
    "method.response.header.Access-Control-Allow-Origin"  = "'https://chat.pandoracloud.net'"
  }
  depends_on = [aws_api_gateway_integration.options_integration]
}

# Cognito Authorizer
resource "aws_api_gateway_authorizer" "cognito" {
  name          = "${var.project_name}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.chat_api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [module.auth.user_pool_arn]
}

resource "aws_api_gateway_domain_name" "api" {
  domain_name              = "chat.pandoracloud.net"
  regional_certificate_arn = module.networking.cert_arn
}

resource "aws_api_gateway_usage_plan" "chat_plan" {
  name = "${var.project_name}-usage-plan"
  api_stages {
    api_id = aws_api_gateway_rest_api.chat_api.id
    stage  = aws_api_gateway_deployment.chat_deployment.stage_name
  }
  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }
}

resource "aws_api_gateway_deployment" "chat_deployment" {
  rest_api_id = aws_api_gateway_rest_api.chat_api.id
  stage_name  = "prod"
  depends_on  = [
    aws_api_gateway_integration.auth_integration,
    aws_api_gateway_integration.chat_integration,
    aws_api_gateway_integration.history_integration,
    aws_api_gateway_integration.options_integration
  ]
}
EOF

cat << 'EOF' > terraform/modules/compute/variables.tf || { echo "Failed to create terraform/modules/compute/variables.tf"; exit 1; }
# terraform/modules/compute/variables.tf
variable "project_name" {
  type = string
}

variable "lambda_role_arn" {
  type = string
}

variable "dynamodb_table" {
  type = string
}

variable "dlq_arn" {
  type = string
}
EOF

cat << 'EOF' > terraform/modules/compute/outputs.tf || { echo "Failed to create terraform/modules/compute/outputs.tf"; exit 1; }
# terraform/modules/compute/outputs.tf
output "api_arn" {
  value = aws_api_gateway_rest_api.chat_api.arn
}
EOF

cat << 'EOF' > terraform/modules/iam/main.tf || { echo "Failed to create terraform/modules/iam/main.tf"; exit 1; }
# terraform/modules/iam/main.tf
variable "project_name" {
  type = string
}

variable "region" {
  type = string
}

variable "dynamodb_table" {
  type = string
}

variable "dlq_arn" {
  type = string
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem"
        ]
        Resource = "arn:aws:dynamodb:${var.region}:*:table/${var.dynamodb_table}"
      },
      {
        Effect = "Allow"
        Action = "bedrock:InvokeModel"
        Resource = "arn:aws:bedrock:${var.region}::foundation-model/amazon.titan-text-*"
      },
      {
        Effect = "Allow"
        Action = "ssm:GetParameter"
        Resource = "arn:aws:ssm:${var.region}:*:parameter/${var.project_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = "sqs:SendMessage"
        Resource = var.dlq_arn
      },
      {
        Effect = "Allow"
        Action = "xray:PutTraceSegments"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "authenticated_role" {
  name = "${var.project_name}-authenticated-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "cognito-identity.amazonaws.com"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "cognito-identity.amazonaws.com:aud" = module.auth.identity_pool_id
        }
        "ForAnyValue:StringLike" = {
          "cognito-identity.amazonaws.com:amr" = "authenticated"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "authenticated_policy" {
  role = aws_iam_role.authenticated_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cognito-identity:*",
          "cognito-idp:*"
        ]
        Resource = "*"
      }
    ]
  })
}
EOF

cat << 'EOF' > terraform/modules/iam/outputs.tf || { echo "Failed to create terraform/modules/iam/outputs.tf"; exit 1; }
# terraform/modules/iam/outputs.tf
output "lambda_exec_arn" {
  value = aws_iam_role.lambda_exec.arn
}
EOF

cat << 'EOF' > terraform/modules/monitoring/main.tf || { echo "Failed to create terraform/modules/monitoring/main.tf"; exit 1; }
# terraform/modules/monitoring/main.tf
variable "project_name" {
  type = string
}

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
EOF

cat << 'EOF' > terraform/modules/monitoring/outputs.tf || { echo "Failed to create terraform/modules/monitoring/outputs.tf"; exit 1; }
# terraform/modules/monitoring/outputs.tf
output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}
EOF

cat << 'EOF' > terraform/modules/networking/main.tf || { echo "Failed to create terraform/modules/networking/main.tf"; exit 1; }
# terraform/modules/networking/main.tf
data "aws_route53_zone" "existing" {
  name = "pandoracloud.net."
}

resource "aws_acm_certificate" "cert" {
  domain_name       = "chat.pandoracloud.net"
  validation_method = "DNS"
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  zone_id = data.aws_route53_zone.existing.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_route53_record" "custom_domain" {
  zone_id = data.aws_route53_zone.existing.zone_id
  name    = "chat.pandoracloud.net"
  type    = "A"
  alias {
    name                   = aws_api_gateway_domain_name.api.domain_name
    zone_id                = aws_api_gateway_domain_name.api.hosted_zone_id
    evaluate_target_health = false
  }
}
EOF

cat << 'EOF' > terraform/modules/networking/outputs.tf || { echo "Failed to create terraform/modules/networking/outputs.tf"; exit 1; }
# terraform/modules/networking/outputs.tf
output "cert_arn" {
  value = aws_acm_certificate.cert.arn
}
EOF

cat << 'EOF' > terraform/modules/security/main.tf || { echo "Failed to create terraform/modules/security/main.tf"; exit 1; }
# terraform/modules/security/main.tf
variable "project_name" {
  type = string
}

variable "api_arn" {
  type = string
}

resource "aws_kms_key" "chat_key" {
  description = "Key for chatbot data encryption"
}

resource "aws_wafv2_web_acl" "api_protection" {
  name        = "${var.project_name}-web-acl"
  scope       = "REGIONAL"
  default_action { allow {} }
  rule {
    name     = "rate-limit"
    priority = 1
    action { block {} }
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
EOF

cat << 'EOF' > terraform/modules/security/outputs.tf || { echo "Failed to create terraform/modules/security/outputs.tf"; exit 1; }
# terraform/modules/security/outputs.tf
output "kms_key_arn" {
  value = aws_kms_key.chat_key.arn
}
EOF

cat << 'EOF' > terraform/modules/storage/main.tf || { echo "Failed to create terraform/modules/storage/main.tf"; exit 1; }
# terraform/modules/storage/main.tf
variable "project_name" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project_name}-frontend"
}

resource "aws_s3_bucket_cors_configuration" "frontend_cors" {
  bucket = aws_s3_bucket.frontend.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["https://chat.pandoracloud.net"]
    max_age_seconds = 3000
  }
}

resource "aws_dynamodb_table" "chat_history" {
  name           = "${var.project_name}-ChatHistory"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "userId"
  range_key      = "sessionId"
  attribute {
    name = "userId"
    type = "S"
  }
  attribute {
    name = "sessionId"
    type = "S"
  }
  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }
}

resource "aws_sqs_queue" "dlq" {
  name = "${var.project_name}-lambda-dlq"
}
EOF

cat << 'EOF' > terraform/modules/storage/outputs.tf || { echo "Failed to create terraform/modules/storage/outputs.tf"; exit 1; }
# terraform/modules/storage/outputs.tf
output "chat_history_table_name" {
  value = aws_dynamodb_table.chat_history.name
}

output "dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}
EOF
