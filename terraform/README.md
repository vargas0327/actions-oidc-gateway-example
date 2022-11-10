# Terraform AWS example 

To spin up a test environment (assuming VPC and subnets already exist):

```sh
cd terraform

# Set your AWS environment variables
cat > terraform.auto.tfvars.example << EOF
github = {
  username = "<YOUR USERNAME>"
  password = "<PAT TOKEN>"
}
vpc = {
  id              = "<VPC>"
  public_subnets  = ["<PUB1>", "<PUB2>"]
  private_subnets = ["<PRIV1>", "<PRIV2>"]
}
proxy_allowed_github_owners = ["ruial", "<YOUR ORG>"]
EOF

AWS_PROFILE=<YOUR PROFILE> terraform apply
```

For production environments make sure to configure remote state, I would recommend Terragrunt, and harden this setup according to your security and network requirements.

To enable TLS on the network load balancer, you need to add a new listener with protocol TLS and you can generate a free certificate from AWS Certificate Manager, if you have control of your public DNS zone in Route53 or another DNS provider.
