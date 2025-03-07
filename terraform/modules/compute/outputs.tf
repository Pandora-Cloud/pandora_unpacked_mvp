# terraform/modules/compute/outputs.tf
output "api_arn" {
  value = aws_api_gateway_rest_api.chat_api.arn
}

# In modules/compute/outputs.tf
output "api_id" {
  value = aws_api_gateway_rest_api.chat_api.id
}

# In modules/compute/outputs.tf
output "api_domain_name" {
  value = aws_api_gateway_domain_name.api.domain_name
}

output "api_hosted_zone_id" {
  value = aws_api_gateway_domain_name.api.regional_zone_id
}

output "stage_name" {
  value = "prod"
}

output "api_gateway_domain_regional_domain_name" {
  value = aws_api_gateway_domain_name.api.regional_domain_name
}

output "api_gateway_domain_regional_zone_id" {
  value = aws_api_gateway_domain_name.api.regional_zone_id
}