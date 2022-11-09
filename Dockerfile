FROM golang:1.19 AS builder
RUN useradd -u 10001 scratchuser
WORKDIR /build

COPY go.mod go.sum ./
RUN go mod download && go mod verify

COPY . .
RUN CGO_ENABLED=0 go build -o app ./actions_oidc_proxy.go

FROM scratch
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /build/app .
USER scratchuser
ENTRYPOINT ["./app"]
