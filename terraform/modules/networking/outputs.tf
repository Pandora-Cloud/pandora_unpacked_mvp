output "cert_arn" {
  value = aws_acm_certificate.cert.arn
}

output "cloudfront_cert_arn" {
  value = aws_acm_certificate.cloudfront_cert.arn
}

output "zone_id" {
  value = data.aws_route53_zone.existing.zone_id
}