package auth

import (
	"bytes"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"strings"
	"time"
)

const accessTokenAudience = "aphrodite-api"

var ErrAccessTokenInvalid = errors.New("access token invalid")

type AccessTokenClaims struct {
	AccountID string
	DeviceID  string
	SessionID string
	IssuedAt  time.Time
	ExpiresAt time.Time
}

type AccessTokenVerifier interface {
	VerifyAccessToken(token string) (AccessTokenClaims, error)
}

type ed25519AccessTokenIssuer struct {
	privateKey ed25519.PrivateKey
	now        Clock
}

type ed25519AccessTokenVerifier struct {
	publicKey ed25519.PublicKey
	now       Clock
}

type accessTokenHeader struct {
	Algorithm string `json:"alg"`
	Type      string `json:"typ"`
	Version   int    `json:"v"`
}

type accessTokenPayload struct {
	Audience  string `json:"aud"`
	AccountID string `json:"sub"`
	DeviceID  string `json:"device_id"`
	SessionID string `json:"session_id"`
	IssuedAt  int64  `json:"iat"`
	ExpiresAt int64  `json:"exp"`
}

func NewEd25519AccessTokenIssuer(privateKey ed25519.PrivateKey, now Clock) (AccessTokenIssuer, error) {
	if len(privateKey) != ed25519.PrivateKeySize {
		return nil, errors.New("access token private key must be an Ed25519 private key")
	}
	if now == nil {
		now = time.Now
	}
	return ed25519AccessTokenIssuer{privateKey: append(ed25519.PrivateKey(nil), privateKey...), now: now}, nil
}

func NewEd25519AccessTokenVerifier(publicKey ed25519.PublicKey, now Clock) (AccessTokenVerifier, error) {
	if len(publicKey) != ed25519.PublicKeySize {
		return nil, errors.New("access token public key must be an Ed25519 public key")
	}
	if now == nil {
		now = time.Now
	}
	return ed25519AccessTokenVerifier{publicKey: append(ed25519.PublicKey(nil), publicKey...), now: now}, nil
}

func (issuer ed25519AccessTokenIssuer) IssueAccessToken(accountID, deviceID, sessionID string, expiresAt time.Time) (string, error) {
	issuedAt := issuer.now().UTC()
	expiresAt = expiresAt.UTC()
	if strings.TrimSpace(accountID) == "" || strings.TrimSpace(deviceID) == "" ||
		strings.TrimSpace(sessionID) == "" || !expiresAt.After(issuedAt) {
		return "", ErrAccessTokenInvalid
	}
	header, err := json.Marshal(accessTokenHeader{Algorithm: "EdDSA", Type: "APT", Version: 1})
	if err != nil {
		return "", err
	}
	payload, err := json.Marshal(accessTokenPayload{
		Audience: accessTokenAudience, AccountID: accountID, DeviceID: deviceID, SessionID: sessionID,
		IssuedAt: issuedAt.Unix(), ExpiresAt: expiresAt.Unix(),
	})
	if err != nil {
		return "", err
	}
	encodedHeader := base64.RawURLEncoding.EncodeToString(header)
	encodedPayload := base64.RawURLEncoding.EncodeToString(payload)
	signingInput := encodedHeader + "." + encodedPayload
	signature := ed25519.Sign(issuer.privateKey, []byte(signingInput))
	return signingInput + "." + base64.RawURLEncoding.EncodeToString(signature), nil
}

func (verifier ed25519AccessTokenVerifier) VerifyAccessToken(token string) (AccessTokenClaims, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 || parts[0] == "" || parts[1] == "" || parts[2] == "" {
		return AccessTokenClaims{}, ErrAccessTokenInvalid
	}
	signature, err := base64.RawURLEncoding.Strict().DecodeString(parts[2])
	if err != nil || len(signature) != ed25519.SignatureSize ||
		!ed25519.Verify(verifier.publicKey, []byte(parts[0]+"."+parts[1]), signature) {
		return AccessTokenClaims{}, ErrAccessTokenInvalid
	}
	var header accessTokenHeader
	if err := decodeAccessTokenPart(parts[0], &header); err != nil ||
		header.Algorithm != "EdDSA" || header.Type != "APT" || header.Version != 1 {
		return AccessTokenClaims{}, ErrAccessTokenInvalid
	}
	var payload accessTokenPayload
	if err := decodeAccessTokenPart(parts[1], &payload); err != nil ||
		payload.Audience != accessTokenAudience || strings.TrimSpace(payload.AccountID) == "" ||
		strings.TrimSpace(payload.DeviceID) == "" || strings.TrimSpace(payload.SessionID) == "" {
		return AccessTokenClaims{}, ErrAccessTokenInvalid
	}
	issuedAt := time.Unix(payload.IssuedAt, 0).UTC()
	expiresAt := time.Unix(payload.ExpiresAt, 0).UTC()
	if !expiresAt.After(issuedAt) || !verifier.now().UTC().Before(expiresAt) {
		return AccessTokenClaims{}, ErrAccessTokenInvalid
	}
	return AccessTokenClaims{
		AccountID: payload.AccountID, DeviceID: payload.DeviceID, SessionID: payload.SessionID,
		IssuedAt: issuedAt, ExpiresAt: expiresAt,
	}, nil
}

func decodeAccessTokenPart(encoded string, destination any) error {
	decoded, err := base64.RawURLEncoding.Strict().DecodeString(encoded)
	if err != nil {
		return err
	}
	decoder := json.NewDecoder(bytes.NewReader(decoded))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return errors.New("access token contains trailing JSON values")
	}
	return nil
}
