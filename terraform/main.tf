terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {}

module "actions_oidc_proxy" {
  source = "./modules/actions-oidc-proxy"

  github                      = var.github
  vpc                         = var.vpc
  proxy_allowed_github_owners = var.proxy_allowed_github_owners
}
