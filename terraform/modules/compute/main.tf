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
  for_each = {
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
  for_each = {
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
  for_each = {
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
  for_each = {
    "auth"    = aws_api_gateway_resource.auth.id,
    "chat"    = aws_api_gateway_resource.chat_session.id,
    "history" = aws_api_gateway_resource.history.id
  }
  rest_api_id   = aws_api_gateway_rest_api.chat_api.id
  resource_id             = each.value
  http_method             = "OPTIONS"
  status_code             = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,POST,GET'"
    "method.response.header.Access-Control-Allow-Origin"  = "'https://chat.dev.pandoracloud.net'"
  }
  depends_on = [aws_api_gateway_integration.options_integration]
}

# Cognito Authorizer
resource "aws_api_gateway_authorizer" "cognito" {
  name          = "${var.project_name}-cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.chat_api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [var.user_pool_arn]
}

resource "aws_api_gateway_deployment" "chat_deployment" {
  rest_api_id = aws_api_gateway_rest_api.chat_api.id
  depends_on  = [
    aws_api_gateway_integration.auth_integration,
    aws_api_gateway_integration.chat_integration,
    aws_api_gateway_integration.history_integration,
    aws_api_gateway_integration.options_integration
  ]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.chat_api.id
  deployment_id = aws_api_gateway_deployment.chat_deployment.id
  stage_name    = "prod"
}

resource "aws_api_gateway_usage_plan" "chat_plan" {
  name = "${var.project_name}-usage-plan"
  api_stages {
    api_id = aws_api_gateway_rest_api.chat_api.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }
  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }
}

resource "aws_api_gateway_domain_name" "api" {
  domain_name              = "chat.dev.pandoracloud.net"
  regional_certificate_arn = var.cert_arn
}