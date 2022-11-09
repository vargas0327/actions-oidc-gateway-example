locals {
  proxy_port_internal = 8080
  proxy_port_external = 80
  aws_region          = data.aws_region.current.name
}
