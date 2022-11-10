# actions-oidc-proxy

[![Run CI](https://github.com/ruial/actions-oidc-proxy/actions/workflows/ci.yml/badge.svg)](https://github.com/ruial/actions-oidc-proxy/actions/workflows/ci.yml)

This project was [forked](https://github.com/github/actions-oidc-gateway-example) to provide a more complete example of how to connect to HTTPS services hosted behind a private network, from a GitHub-hosted Actions runner.

This Go implementation acts as an HTTP CONNECT proxy tunnel and allows you to customize some environment variables to secure access to your private services:

```sh
# check claims (allowed repository owners/names, audience) and hosts
# a wildcard matches anything and all rules are evaluated
export ACTIONS_OIDC_PROXY_OWNERS=ruial,github
export ACTIONS_OIDC_PROXY_REPOS=*
export ACTIONS_OIDC_PROXY_AUDS=*
export ACTIONS_OIDC_PROXY_HOSTS=*
# run the proxy app
go run actions_oidc_proxy.go
# a sample request
https_proxy=http://anyuser:TOKEN@localhost:8080 curl -v --max-time 3 https://ipv4.icanhazip.com
```

The proxy can be deployed behind a public load balancer, ideally with TLS, allowing access to internal services in a private VPC or on-prem network, without having to deploy self-hosted runners. By using [GitHub's OIDC provider](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect#configuring-the-oidc-trust-with-the-cloud) we can securely authorize requests from the public internet, for certain repositories and hosts, following a zero trust security model.

![deployment](docs/images/deployment.png)

## How would I use this?

Once you customize and deploy your proxy, using the example [AWS Terraform module](terraform), you can configure your Actions workflow to make use of it:

```yaml
...

jobs:
  your_job_name:
    ...
    permissions:
      id-token: write
    steps:
      ...

      - name: Get OIDC token and set OIDC_TOKEN environment variable
        run: |
          echo "OIDC_TOKEN=$(curl -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" -H "Accept: application/json; api-version=2.0" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://ActionsOIDCGateway" | jq -r ".value")" >> $GITHUB_ENV
      - name: Example of a Proxy request
        run: |
          export no_proxy=google.com,amazonaws.com
          export https_proxy=http://user:${{ env.OIDC_TOKEN }}@proxy.briefbytes.com.io:80
          curl --max-time 5 https://ipv4.icanhazip.com
          curl --max-time 5 https://s3.amazonaws.com/test

    ...
```

Many programming languages and tools respect the ```no_proxy``` and ```https_proxy``` environment variables. You can check the following [article](https://about.gitlab.com/blog/2021/01/27/we-need-to-talk-no-proxy/) to read more about the topic. A similar setup is commonly used by enterprises with HAproxy and Squid to better restrict and monitor HTTPS traffic. However, only the Host, Proxy Headers and metadata like Source IP are actually accessible, as the traffic is encrypted, so additional data, like the request path or body are unreadable by a proxy. You may also consider [WireGuard](https://docs.github.com/en/actions/using-github-hosted-runners/connecting-to-a-private-network) as an alternative to a proxy or API gateway.
