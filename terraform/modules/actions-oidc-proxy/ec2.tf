resource "aws_security_group" "actions_oidc_proxy_service" {
  name   = "${var.app_name}_service_sg"
  vpc_id = var.vpc.id

  ingress {
    protocol    = "TCP"
    from_port   = local.proxy_port_internal
    to_port     = local.proxy_port_internal
    cidr_blocks = var.cidr_blocks_ingress
  }

  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = var.cidr_blocks_egress
  }
}

# Needs to be a network load balancer, otherwise HTTP CONNECT will return error 400 with ALB
resource "aws_lb" "actions_oidc_proxy_nlb" {
  name               = replace("${var.app_name}_nlb", "_", "-")
  load_balancer_type = "network"
  subnets            = var.vpc.public_subnets
}

resource "aws_lb_target_group" "actions_oidc_proxy_nlb_target" {
  name        = replace("${var.app_name}_nlb_target", "_", "-")
  port        = local.proxy_port_internal
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = var.vpc.id

  preserve_client_ip = true

  stickiness {
    enabled = true
    type    = "source_ip"
  }

  health_check {
    protocol = "HTTP"
    port     = local.proxy_port_internal
    path     = "/ping"
  }
}

resource "aws_lb_listener" "actions_oidc_proxy_nlb_listener" {
  load_balancer_arn = aws_lb.actions_oidc_proxy_nlb.arn
  port              = local.proxy_port_external
  protocol          = "TCP"

  default_action {
    target_group_arn = aws_lb_target_group.actions_oidc_proxy_nlb_target.arn
    type             = "forward"
  }
}
