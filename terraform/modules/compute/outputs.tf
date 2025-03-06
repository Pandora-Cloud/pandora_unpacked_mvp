# terraform/modules/compute/outputs.tf
output "api_arn" {
  value = aws_api_gateway_rest_api.chat_api.arn
}
