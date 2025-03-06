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
  callback_urls = ["https://chat.dev.pandoracloud.net/callback"]
  logout_urls   = ["https://chat.dev.pandoracloud.net/logout"]
}

resource "aws_cognito_identity_pool" "chat_identity_pool" {
  identity_pool_name               = "${var.project_name}-IdentityPool"
  allow_unauthenticated_identities = true
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

