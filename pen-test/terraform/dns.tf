# Route 53 DNS configuration (optional).
#
# This file only creates resources when `domain_name` is set to a non-empty
# value AND points to a Route 53 hosted zone you own in this AWS account.
#
# If you don't have a Route 53 hosted zone, leave `domain_name` empty (the
# default) and use the raw ALB DNS name from the `alb_dns_name` output as your
# pen test target instead.

locals {
  use_custom_domain = var.domain_name != ""
}

data "aws_route53_zone" "main" {
  count = local.use_custom_domain ? 1 : 0
  name  = var.domain_name
}

resource "aws_route53_record" "pentest" {
  count   = local.use_custom_domain ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = "pentest.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.vulnerable_alb.dns_name
    zone_id                = aws_lb.vulnerable_alb.zone_id
    evaluate_target_health = true
  }
}

output "pentest_domain" {
  description = "Domain for pen testing. Empty if no custom domain was configured; use `alb_dns_name` output instead."
  value       = local.use_custom_domain ? "http://pentest.${var.domain_name}" : ""
}
