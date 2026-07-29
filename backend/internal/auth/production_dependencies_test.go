package auth

import (
	"strings"
	"testing"

	"golang.org/x/crypto/bcrypt"
)

func TestSecureCredentialGeneratorProducesOpaqueCredentials(t *testing.T) {
	generator := SecureCredentialGenerator{}
	first, err := generator.NewOpaqueCredential("refresh")
	if err != nil {
		t.Fatalf("NewOpaqueCredential() error = %v", err)
	}
	second, err := generator.NewOpaqueCredential("refresh")
	if err != nil {
		t.Fatalf("NewOpaqueCredential() error = %v", err)
	}
	if !strings.HasPrefix(first, "refresh_") || first == second {
		t.Fatalf("unexpected credentials: first=%q second=%q", first, second)
	}
	if _, err := generator.NewOpaqueCredential(""); err == nil {
		t.Fatal("empty prefix must fail")
	}
}

func TestRandomIDGeneratorProducesUUIDv4(t *testing.T) {
	id, err := (RandomIDGenerator{}).NewID("session")
	if err != nil {
		t.Fatalf("NewID() error = %v", err)
	}
	if len(id) != 36 || id[14] != '4' || id[8] != '-' || id[13] != '-' || id[18] != '-' || id[23] != '-' {
		t.Fatalf("invalid UUIDv4 shape: %q", id)
	}
	if _, err := (RandomIDGenerator{}).NewID(""); err == nil {
		t.Fatal("empty prefix must fail")
	}
}

func TestBcryptPasswordVerifier(t *testing.T) {
	hash, err := bcrypt.GenerateFromPassword([]byte("example-password"), bcrypt.MinCost)
	if err != nil {
		t.Fatalf("GenerateFromPassword() error = %v", err)
	}
	verifier := BcryptPasswordVerifier{}
	if err := verifier.VerifyPassword(string(hash), "example-password"); err != nil {
		t.Fatalf("VerifyPassword() error = %v", err)
	}
	if err := verifier.VerifyPassword(string(hash), "wrong-example-password"); err != ErrInvalidCredentials {
		t.Fatalf("wrong password error = %v", err)
	}
}
