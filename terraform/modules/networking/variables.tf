# In modules/networking/variables.tf
variable "api_id" {
  type = string
  description = "The API Gateway ID to associate with the domain"
}

variable "api_domain_name" {
  type = string
  description = "The domain name for the API Gateway"
}

variable "api_hosted_zone_id" {
  type = string
  description = "The hosted zone ID for the API Gateway domain"
}

variable "api_gateway_domain_regional_domain_name" {
  description = "Regional domain name for API Gateway"
  type        = string
}

variable "api_gateway_domain_regional_zone_id" {
  description = "Regional zone ID for API Gateway"
  type        = string
}