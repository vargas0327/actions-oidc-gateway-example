data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    actions = [
      "sts:AssumeRole"
    ]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${var.app_name}_ecs_task_execution_role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

data "aws_iam_policy_document" "ecs_task_execution_policy" {
  statement {
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html
    resources = [
      "*"
    ]
  }
}

resource "aws_iam_role_policy" "grant_ecs_access" {
  name   = "${var.app_name}_ecs_access"
  role   = aws_iam_role.ecs_task_execution_role.name
  policy = data.aws_iam_policy_document.ecs_task_execution_policy.json
}

data "aws_iam_policy_document" "github_credentials" {
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue"
    ]

    resources = [
      aws_secretsmanager_secret.github_credentials.arn
    ]
  }
}

resource "aws_iam_role_policy" "grant_github_credentials" {
  name   = "${var.app_name}_grant_github_credentials"
  role   = aws_iam_role.ecs_task_execution_role.name
  policy = data.aws_iam_policy_document.github_credentials.json
}
