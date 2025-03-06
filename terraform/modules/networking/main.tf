# terraform/modules/networking/main.tf
data "aws_route53_zone" "existing" {
  name = "pandoracloud.net."
}

resource "aws_acm_certificate" "cert" {
  domain_name       = "chat.pandoracloud.net"
  validation_method = "DNS"
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  zone_id = data.aws_route53_zone.existing.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_route53_record" "custom_domain" {
  zone_id = data.aws_route53_zone.existing.zone_id
  name    = "chat.pandoracloud.net"
  type    = "A"
  alias {
    name                   = aws_api_gateway_domain_name.api.domain_name
    zone_id                = aws_api_gateway_domain_name.api.hosted_zone_id
    evaluate_target_health = false
  }
}
