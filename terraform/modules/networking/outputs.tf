# terraform/modules/networking/outputs.tf
output "cert_arn" {
  value = aws_acm_certificate.cert.arn
}
