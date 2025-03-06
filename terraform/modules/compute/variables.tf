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
