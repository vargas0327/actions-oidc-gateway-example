# Another Go Makefile example: https://github.com/ruial/busca

run:
	ACTIONS_OIDC_PROXY_OWNERS=ruial go run -race actions_oidc_proxy.go

test:
	go test -v -race ./...

request-https:
	@https_proxy=http://user:${GITHUB_OIDC_TOKEN}@localhost:8080 curl -v --max-time 3 https://ipv4.icanhazip.com

request-https-noproxy:
	@no_proxy=amazonaws.com http_proxy=http://user:${GITHUB_OIDC_TOKEN}@localhost:8080 curl -v --max-time 3 https://s3.amazonaws.com/test

request-http:
	@http_proxy=http://user:${GITHUB_OIDC_TOKEN}@localhost:8080 curl -v --max-time 3 http://ipv4.icanhazip.com

request-http-connect:
	@http_proxy=http://user:${GITHUB_OIDC_TOKEN}@localhost:8080 curl -v --max-time 3 --proxytunnel http://ipv4.icanhazip.com
