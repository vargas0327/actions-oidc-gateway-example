resource "aws_secretsmanager_secret" "github_credentials" {
  name = "${var.app_name}_github_credentials"
}

resource "aws_secretsmanager_secret_version" "github_credentials" {
  secret_id     = aws_secretsmanager_secret.github_credentials.id
  secret_string = jsonencode(var.github)
}
