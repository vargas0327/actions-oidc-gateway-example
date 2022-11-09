package main

import (
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"math/big"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v4"
)

type JWK struct {
	N   string
	Kty string
	Kid string
	Alg string
	E   string
	Use string
	X5c []string
	X5t string
}

type JWKS struct {
	Keys []JWK
}

type GatewayContext struct {
	jwksCache      []byte
	jwksLastUpdate time.Time
	allowedOwners  map[string]bool
	allowedRepos   map[string]bool
	allowedAuds    map[string]bool
	allowedHosts   map[string]bool
	sync.Mutex
}

func getKeyFromJwks(jwksBytes []byte) func(*jwt.Token) (interface{}, error) {
	return func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, fmt.Errorf("Unexpected signing method: %v", token.Header["alg"])
		}

		var jwks JWKS
		if err := json.Unmarshal(jwksBytes, &jwks); err != nil {
			return nil, fmt.Errorf("Unable to parse JWKS")
		}

		for _, jwk := range jwks.Keys {
			if jwk.Kid == token.Header["kid"] {
				nBytes, err := base64.RawURLEncoding.DecodeString(jwk.N)
				if err != nil {
					return nil, fmt.Errorf("Unable to parse key")
				}
				var n big.Int

				eBytes, err := base64.RawURLEncoding.DecodeString(jwk.E)
				if err != nil {
					return nil, fmt.Errorf("Unable to parse key")
				}
				var e big.Int

				key := rsa.PublicKey{
					N: n.SetBytes(nBytes),
					E: int(e.SetBytes(eBytes).Uint64()),
				}

				return &key, nil
			}
		}

		return nil, fmt.Errorf("Unknown kid: %v", token.Header["kid"])
	}
}

func validateTokenCameFromGitHub(oidcTokenString string, gc *GatewayContext) (jwt.MapClaims, error) {
	// Check if we have a recently cached JWKS
	now := time.Now()

	// Could use channels or a RWMutex but this is the simplest approach to remove data race warnings
	// Read more about concurrency in https://rauljordan.com/2021/01/05/reuse-expensive-computation-with-in-progress-caches.html
	gc.Lock()
	defer gc.Unlock()

	if now.Sub(gc.jwksLastUpdate) > time.Minute || len(gc.jwksCache) == 0 {
		resp, err := http.Get("https://token.actions.githubusercontent.com/.well-known/jwks")
		if err != nil {
			log.Println(err)
			return nil, fmt.Errorf("Unable to get JWKS configuration")
		}

		jwksBytes, err := ioutil.ReadAll(resp.Body)
		if err != nil {
			log.Println(err)
			return nil, fmt.Errorf("Unable to get JWKS configuration")
		}

		gc.jwksCache = jwksBytes
		gc.jwksLastUpdate = now
	}

	// Attempt to validate JWT with JWKS
	oidcToken, err := jwt.Parse(oidcTokenString, getKeyFromJwks(gc.jwksCache))
	if err != nil || !oidcToken.Valid {
		return nil, fmt.Errorf("Unable to validate JWT")
	}

	claims, ok := oidcToken.Claims.(jwt.MapClaims)
	if !ok {
		return nil, fmt.Errorf("Unable to map JWT claims")
	}

	return claims, nil
}

func transfer(destination io.WriteCloser, source io.ReadCloser) {
	defer destination.Close()
	defer source.Close()
	io.Copy(destination, source)
}

func handleProxyRequest(w http.ResponseWriter, req *http.Request) {
	proxyConn, err := net.DialTimeout("tcp", req.Host, 5*time.Second)
	if err != nil {
		log.Println(err)
		http.Error(w, http.StatusText(http.StatusRequestTimeout), http.StatusRequestTimeout)
		return
	}

	w.WriteHeader(http.StatusOK)

	hijacker, ok := w.(http.Hijacker)
	if !ok {
		log.Println("Connection hijacking not supported")
		http.Error(w, http.StatusText(http.StatusExpectationFailed), http.StatusExpectationFailed)
		return
	}

	reqConn, _, err := hijacker.Hijack()
	if err != nil {
		log.Println(err)
		http.Error(w, http.StatusText(http.StatusBadRequest), http.StatusBadRequest)
		return
	}

	go transfer(proxyConn, reqConn)
	go transfer(reqConn, proxyConn)
}

func isValidClaim(claimKey string, claims jwt.MapClaims, allowedClaimValues map[string]bool) bool {
	authorized := true
	claimValue := claims[claimKey].(string)
	if !allowedClaimValues[claimValue] && !allowedClaimValues["*"] {
		log.Printf("Unauthorized claim %s: %s", claimKey, claimValue)
		authorized = false
	}
	return authorized
}

func (gatewayContext *GatewayContext) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	if req.Method == http.MethodGet && strings.ToLower(req.URL.Path) == "/ping" {
		fmt.Fprintln(w, "PONG")
		return
	}

	// This http server only functions as an HTTP CONNECT proxy tunnel
	if req.Method != http.MethodConnect {
		http.Error(w, http.StatusText(http.StatusMethodNotAllowed), http.StatusMethodNotAllowed)
		return
	}

	// Only Proxy Basic Auth credentials supported which are encoded in base64
	b64credentials := strings.TrimPrefix(req.Header.Get("Proxy-Authorization"), "Basic ")
	credentials, err := base64.StdEncoding.DecodeString(b64credentials)
	if err != nil {
		log.Println(err)
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

	// We are interested in the password, which has the oidc token
	credentialsParts := strings.Split(string(credentials), ":")
	if len(credentialsParts) != 2 {
		log.Println("Proxy-Authorization header required")
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}
	oidcTokenString := credentialsParts[1]

	// Check if the OIDC token came from any GitHub Actions workflow
	claims, err := validateTokenCameFromGitHub(oidcTokenString, gatewayContext)
	if err != nil {
		log.Println(err)
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

	// Token is valid, but we *must* check some claim specific to our use case
	// https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect#configuring-the-oidc-trust-with-the-cloud
	if !isValidClaim("repository_owner", claims, gatewayContext.allowedOwners) {
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

	// Also verifying the repository name
	if !isValidClaim("repository", claims, gatewayContext.allowedRepos) {
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

	// You can customize the audience when you request an Actions OIDC token.
	// This is a good idea to prevent a token being accidentally leaked by a service from being used in another service.
	if !isValidClaim("aud", claims, gatewayContext.allowedAuds) {
		http.Error(w, http.StatusText(http.StatusUnauthorized), http.StatusUnauthorized)
		return
	}

	// Check if the request host is allowed
	host := strings.Split(req.Host, ":")[0]
	if !gatewayContext.allowedHosts[host] && !gatewayContext.allowedHosts["*"] {
		log.Println("Forbidden host:", host)
		http.Error(w, http.StatusText(http.StatusForbidden), http.StatusForbidden)
		return
	}

	// Now that claims and host have been verified, we can service the request
	handleProxyRequest(w, req)

	log.Println("Handled request:", host, ":", claims["repository"], ":", claims["aud"])
}

func sliceToSet[K comparable](s []K) map[K]bool {
	m := make(map[K]bool, len(s))
	for _, val := range s {
		m[val] = true
	}
	return m
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}

func main() {
	// Simple default logger is enough here, for structured logging see https://www.honeybadger.io/blog/golang-logging/
	log.SetFlags(log.Ldate | log.Ltime | log.Lshortfile)

	port := getEnv("ACTIONS_OIDC_PROXY_PORT", "8000")
	// Wildcards mean allow all, should always customize owner and/or repos/aud for security
	owners := strings.Split(getEnv("ACTIONS_OIDC_PROXY_OWNERS", "*"), ",")
	repos := strings.Split(getEnv("ACTIONS_OIDC_PROXY_REPOS", "*"), ",")
	auds := strings.Split(getEnv("ACTIONS_OIDC_PROXY_AUDS", "*"), ",")
	hosts := strings.Split(getEnv("ACTIONS_OIDC_PROXY_HOSTS", "*"), ",")

	gatewayContext := &GatewayContext{
		jwksLastUpdate: time.Now(),
		allowedOwners:  sliceToSet(owners),
		allowedRepos:   sliceToSet(repos),
		allowedAuds:    sliceToSet(auds),
		allowedHosts:   sliceToSet(hosts),
	}

	server := http.Server{
		Addr:         ":" + port,
		Handler:      gatewayContext,
		ReadTimeout:  60 * time.Second,
		WriteTimeout: 60 * time.Second,
	}

	log.Println("Starting Actions OIDC Proxy on port", port)
	if err := server.ListenAndServe(); err != nil {
		log.Fatalln(err)
	}
}
