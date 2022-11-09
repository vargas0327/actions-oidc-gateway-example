resource "aws_ecs_cluster" "actions_oidc_proxy" {
  name = var.app_name
}

resource "aws_ecs_cluster_capacity_providers" "actions_oidc_proxy" {
  cluster_name = aws_ecs_cluster.actions_oidc_proxy.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

resource "aws_ecs_task_definition" "actions_oidc_proxy" {
  family                   = var.app_name
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  # Available sizes with Fargate: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-error.html
  cpu                   = var.container_cpu
  memory                = var.container_memory
  container_definitions = <<TASK_DEFINITION
[
  {
    "name": "${var.app_name}",
    "image": "${var.container_image}",
    "cpu": ${var.container_cpu},
    "memory": ${var.container_memory},
    "environment": [
      {"name": "ACTIONS_OIDC_PROXY_PORT", "value": "${local.proxy_port_internal}"},
      {"name": "ACTIONS_OIDC_PROXY_OWNERS", "value": "${join(",", var.proxy_allowed_github_owners)}"}
    ],
    "essential": true,
    "portMappings": [
      {
        "containerPort": ${local.proxy_port_internal},
        "hostPort": ${local.proxy_port_internal}
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "${aws_cloudwatch_log_group.actions_oidc_proxy.name}",
        "awslogs-region": "${local.aws_region}",
        "awslogs-stream-prefix": "${var.app_name}"
      }
    },
    "repositoryCredentials" : {
      "credentialsParameter" : "${aws_secretsmanager_secret.github_credentials.arn}"
    }
  }
]
TASK_DEFINITION
}

resource "aws_ecs_service" "actions_oidc_proxy" {
  name            = var.app_name
  cluster         = aws_ecs_cluster.actions_oidc_proxy.id
  task_definition = aws_ecs_task_definition.actions_oidc_proxy.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    security_groups = [aws_security_group.actions_oidc_proxy_service.id]
    subnets         = var.vpc.private_subnets
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.actions_oidc_proxy_nlb_target.arn
    container_name   = var.app_name
    container_port   = local.proxy_port_internal
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

}
