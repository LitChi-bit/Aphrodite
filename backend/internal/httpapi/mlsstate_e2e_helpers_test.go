package httpapi

import (
	"crypto/ed25519"
	"crypto/rand"
	"testing"
	"time"

	"aphrodite/backend/internal/auth"
)

func newMLSStateE2ETokenPair(t *testing.T) (auth.AccessTokenIssuer, auth.AccessTokenVerifier) {
	t.Helper()
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate MLS E2E token key: %v", err)
	}
	issuer, err := auth.NewEd25519AccessTokenIssuer(privateKey, time.Now)
	if err != nil {
		t.Fatalf("create MLS E2E token issuer: %v", err)
	}
	verifier, err := auth.NewEd25519AccessTokenVerifier(publicKey, time.Now)
	if err != nil {
		t.Fatalf("create MLS E2E token verifier: %v", err)
	}
	return issuer, verifier
}
