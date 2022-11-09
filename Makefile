# Another Go Makefile example: https://github.com/ruial/busca

run:
	ACTIONS_OIDC_PROXY_OWNERS=ruial go run -race actions_oidc_proxy.go

test:
	go test -v -race ./...

request:
	@no_proxy=s3.amazonaws.com https_proxy=http://:${GITHUB_OIDC_TOKEN}@localhost:8080 curl -v --max-time 3 https://ipv4.icanhazip.com
