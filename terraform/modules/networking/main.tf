provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = "forge_interns_tf"
}

data "aws_route53_zone" "existing" {
  name = "dev.pandoracloud.net."
}

resource "aws_acm_certificate" "cert" {
  domain_name       = "chat.dev.pandoracloud.net"
  validation_method = "DNS"
}

resource "aws_acm_certificate" "cloudfront_cert" {
  provider          = aws.us_east_1
  domain_name       = "chat.dev.pandoracloud.net"
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
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

# Comment out this resource as we'll use the CloudFront one instead
# resource "aws_route53_record" "custom_domain" {
#   zone_id = data.aws_route53_zone.existing.zone_id
#   name    = "chat.dev.pandoracloud.net"
#   type    = "A"
#   alias {
#     name                   = var.api_gateway_domain_regional_domain_name
#     zone_id                = var.api_gateway_domain_regional_zone_id
#     evaluate_target_health = true
#   }
# }