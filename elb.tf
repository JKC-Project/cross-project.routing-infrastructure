resource "aws_lb" "common_lb" {
  name               = "common-load-balancer"
  load_balancer_type = "application"

  security_groups = [aws_security_group.lb_security_group.id]
  subnets         = [for s in aws_subnet.public : s.id]

  internal                   = false
  enable_deletion_protection = true

  access_logs {
    bucket  = aws_s3_bucket.access_logs.id
    prefix  = local.s3_objects_common_load_balancer_prefix
    enabled = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.common_lb.arn

  port     = "80"
  protocol = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.common_lb.arn

  port            = "443"
  protocol        = "HTTPS"
  ssl_policy      = "ELBSecurityPolicy-2016-08" # recommended by AWS
  certificate_arn = module.dummy_default_certificate.tls_cert.arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "502: Bad Gateway"
      status_code  = "502"
    }
  }
}

module "listener_rules_for_ip_targets" {
  for_each = { for a in local.elb_routable_apps : a.fqdn => a }
  source   = "./alb_listeners_and_target_groups"

  fqdn                     = each.key
  project                  = each.value.project
  application              = each.value.application
  vpc_id                   = data.aws_vpc.default_vpc.id
  alb_listener_arn         = aws_lb_listener.https.arn
  target_group_target_type = each.value.target_group_target_type
  health_check_path        = each.value.health_check_path
}

module "all_projects_tls_certificates" {
  for_each = { for a in local.elb_routable_apps : a.fqdn => a }
  source   = "./validated_tls_cert"

  fqdn            = each.value.fqdn
  route53_zone_id = data.aws_ssm_parameter.r53_zoneids[each.value.env_root_domain].value
}

/**
When making a HTTPS listener on an ALB, you must specify a default TLS cert in case a HTTP request's host does not match
any of the attached certificates, so I'm forced to make this dummy TLS cert even though this will never get used
**/
module "dummy_default_certificate" {
  source = "./validated_tls_cert"

  fqdn            = format("dummy-cert.%ssmall.domains", var.environment == "prod" ? "" : "${var.environment}.")
  route53_zone_id = data.aws_ssm_parameter.r53_zoneids[format("%ssmall.domains", var.environment == "prod" ? "" : "${var.environment}.")].value
}

resource "aws_lb_listener_certificate" "listener_certs" {
  for_each        = module.all_projects_tls_certificates
  listener_arn    = aws_lb_listener.https.arn
  certificate_arn = each.value.tls_cert.arn
}