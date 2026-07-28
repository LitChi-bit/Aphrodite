package auth

import (
	"crypto/ed25519"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestEd25519AccessTokenRoundTrip(t *testing.T) {
	now := time.Date(2026, 7, 28, 4, 0, 0, 0, time.UTC)
	privateKey := deterministicEd25519PrivateKey()
	issuer, err := NewEd25519AccessTokenIssuer(privateKey, func() time.Time { return now })
	if err != nil {
		t.Fatalf("new issuer: %v", err)
	}
	verifier, err := NewEd25519AccessTokenVerifier(privateKey.Public().(ed25519.PublicKey), func() time.Time { return now })
	if err != nil {
		t.Fatalf("new verifier: %v", err)
	}

	token, err := issuer.IssueAccessToken("account-example", "device-example", "session-example", now.Add(15*time.Minute))
	if err != nil {
		t.Fatalf("issue access token: %v", err)
	}
	claims, err := verifier.VerifyAccessToken(token)
	if err != nil {
		t.Fatalf("verify access token: %v", err)
	}
	if claims.AccountID != "account-example" || claims.DeviceID != "device-example" || claims.SessionID != "session-example" {
		t.Fatalf("unexpected claims: %#v", claims)
	}
	if !claims.IssuedAt.Equal(now) || !claims.ExpiresAt.Equal(now.Add(15*time.Minute)) {
		t.Fatalf("unexpected timestamps: %#v", claims)
	}
}

func TestEd25519AccessTokenRejectsTamperingAndExpiration(t *testing.T) {
	now := time.Date(2026, 7, 28, 4, 0, 0, 0, time.UTC)
	privateKey := deterministicEd25519PrivateKey()
	issuer, err := NewEd25519AccessTokenIssuer(privateKey, func() time.Time { return now })
	if err != nil {
		t.Fatalf("new issuer: %v", err)
	}
	verifier, err := NewEd25519AccessTokenVerifier(privateKey.Public().(ed25519.PublicKey), func() time.Time { return now })
	if err != nil {
		t.Fatalf("new verifier: %v", err)
	}
	token, err := issuer.IssueAccessToken("account-example", "device-example", "session-example", now.Add(time.Minute))
	if err != nil {
		t.Fatalf("issue access token: %v", err)
	}

	parts := strings.Split(token, ".")
	parts[1] = base64.RawURLEncoding.EncodeToString([]byte(`{"sub":"other-account"}`))
	if _, err := verifier.VerifyAccessToken(strings.Join(parts, ".")); err != ErrAccessTokenInvalid {
		t.Fatalf("tampered token error = %v", err)
	}

	expiredVerifier, err := NewEd25519AccessTokenVerifier(privateKey.Public().(ed25519.PublicKey), func() time.Time { return now.Add(time.Minute) })
	if err != nil {
		t.Fatalf("new expired verifier: %v", err)
	}
	if _, err := expiredVerifier.VerifyAccessToken(token); err != ErrAccessTokenInvalid {
		t.Fatalf("expired token error = %v", err)
	}
}

func TestEd25519AccessTokenRejectsUnsupportedPayloadFields(t *testing.T) {
	now := time.Date(2026, 7, 28, 4, 0, 0, 0, time.UTC)
	privateKey := deterministicEd25519PrivateKey()
	verifier, err := NewEd25519AccessTokenVerifier(privateKey.Public().(ed25519.PublicKey), func() time.Time { return now })
	if err != nil {
		t.Fatalf("new verifier: %v", err)
	}
	header, err := json.Marshal(accessTokenHeader{Algorithm: "EdDSA", Type: "APT", Version: 1})
	if err != nil {
		t.Fatalf("marshal header: %v", err)
	}
	payload, err := json.Marshal(map[string]any{
		"aud": accessTokenAudience, "sub": "account-example", "device_id": "device-example",
		"session_id": "session-example", "iat": now.Unix(), "exp": now.Add(15 * time.Minute).Unix(),
		"admin": true,
	})
	if err != nil {
		t.Fatalf("marshal payload: %v", err)
	}
	signingInput := base64.RawURLEncoding.EncodeToString(header) + "." + base64.RawURLEncoding.EncodeToString(payload)
	token := signingInput + "." + base64.RawURLEncoding.EncodeToString(ed25519.Sign(privateKey, []byte(signingInput)))
	if _, err := verifier.VerifyAccessToken(token); err != ErrAccessTokenInvalid {
		t.Fatalf("unknown field token error = %v", err)
	}
}

func TestEd25519AccessTokenRejectsInvalidKeysAndInputs(t *testing.T) {
	if _, err := NewEd25519AccessTokenIssuer([]byte("invalid"), nil); err == nil {
		t.Fatal("invalid private key must be rejected")
	}
	if _, err := NewEd25519AccessTokenVerifier([]byte("invalid"), nil); err == nil {
		t.Fatal("invalid public key must be rejected")
	}

	now := time.Date(2026, 7, 28, 4, 0, 0, 0, time.UTC)
	issuer, err := NewEd25519AccessTokenIssuer(deterministicEd25519PrivateKey(), func() time.Time { return now })
	if err != nil {
		t.Fatalf("new issuer: %v", err)
	}
	if _, err := issuer.IssueAccessToken("", "device-example", "session-example", now.Add(time.Minute)); err != ErrAccessTokenInvalid {
		t.Fatalf("empty account error = %v", err)
	}
	if _, err := issuer.IssueAccessToken("account-example", "device-example", "session-example", now); err != ErrAccessTokenInvalid {
		t.Fatalf("nonfuture expiry error = %v", err)
	}
}

func deterministicEd25519PrivateKey() ed25519.PrivateKey {
	seed := sha256.Sum256([]byte("aphrodite-test-access-token-key"))
	return ed25519.NewKeyFromSeed(seed[:])
}
