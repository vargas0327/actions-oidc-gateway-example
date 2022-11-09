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

variable "app_name" {
  type    = string
  default = "actions_oidc_proxy"
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "container_cpu" {
  type    = number
  default = 256
}

variable "container_memory" {
  type    = number
  default = 512
}

variable "container_image" {
  type    = string
  default = "ghcr.io/ruial/actions-oidc-proxy:main"
}

variable "cidr_blocks_ingress" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "cidr_blocks_egress" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}
