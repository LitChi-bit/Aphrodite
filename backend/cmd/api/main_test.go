package main

import (
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"testing"
)

func TestAccessTokenPrivateKey(t *testing.T) {
	seed := sha256.Sum256([]byte("aphrodite-test-main-key"))
	privateKey := ed25519.NewKeyFromSeed(seed[:])
	encoded := base64.StdEncoding.EncodeToString(privateKey)

	parsed, err := accessTokenPrivateKey(encoded)
	if err != nil {
		t.Fatalf("accessTokenPrivateKey() error = %v", err)
	}
	if !parsed.Equal(privateKey) {
		t.Fatal("parsed private key differs")
	}
}

func TestAccessTokenPrivateKeyRejectsInvalidInput(t *testing.T) {
	for _, value := range []string{"", "not-base64", base64.StdEncoding.EncodeToString([]byte("short"))} {
		if _, err := accessTokenPrivateKey(value); err == nil {
			t.Fatalf("accessTokenPrivateKey(%q) expected error", value)
		}
	}
}
