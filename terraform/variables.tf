# Populate your terraform.auto.tfvars file with your Github PAT:
# https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
variable "github" {
  type = object({
    username = string
    password = string
  })
}

variable "vpc" {
  type = object({
    id              = string
    public_subnets  = list(string)
    private_subnets = list(string)
  })
}

variable "proxy_allowed_github_owners" {
  type = list(string)
}
