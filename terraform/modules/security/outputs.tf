# terraform/modules/security/outputs.tf
output "kms_key_arn" {
  value = aws_kms_key.chat_key.arn
}
