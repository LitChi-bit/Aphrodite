package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"strings"

	"golang.org/x/crypto/bcrypt"
)

type BcryptPasswordVerifier struct{}

func (BcryptPasswordVerifier) VerifyPassword(encodedHash, password string) error {
	if password == "" || bcrypt.CompareHashAndPassword([]byte(encodedHash), []byte(password)) != nil {
		return ErrInvalidCredentials
	}
	return nil
}

type SHA256TokenHasher struct{}

func (SHA256TokenHasher) HashToken(token string) []byte {
	sum := sha256.Sum256([]byte(token))
	return sum[:]
}

type SecureCredentialGenerator struct{}

func (SecureCredentialGenerator) NewOpaqueCredential(prefix string) (string, error) {
	if strings.TrimSpace(prefix) == "" {
		return "", fmt.Errorf("credential prefix is required")
	}
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", fmt.Errorf("generate credential: %w", err)
	}
	return prefix + "_" + base64.RawURLEncoding.EncodeToString(bytes), nil
}

type RandomIDGenerator struct{}

func (RandomIDGenerator) NewID(prefix string) (string, error) {
	if strings.TrimSpace(prefix) == "" {
		return "", fmt.Errorf("id prefix is required")
	}
	bytes := make([]byte, 16)
	if _, err := rand.Read(bytes); err != nil {
		return "", fmt.Errorf("generate id: %w", err)
	}
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", bytes[0:4], bytes[4:6], bytes[6:8], bytes[8:10], bytes[10:16]), nil
}
