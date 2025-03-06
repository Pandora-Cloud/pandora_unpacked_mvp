# terraform/modules/auth/outputs.tf
output "user_pool_arn" {
  value = aws_cognito_user_pool.chat_pool.arn
}

output "identity_pool_id" {
  value = aws_cognito_identity_pool.chat_identity_pool.id
}
