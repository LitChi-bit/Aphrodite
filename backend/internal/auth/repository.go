package auth

import (
	"context"
	"errors"
	"time"
)

var (
	ErrAccountNotFound     = errors.New("account not found")
	ErrDeviceNotFound      = errors.New("device not found")
	ErrChallengeNotFound   = errors.New("login challenge not found")
	ErrAuthorizationCodeInvalid = errors.New("authorization code invalid")
	ErrSessionNotFound          = errors.New("session not found")
	ErrRefreshTokenInvalid      = errors.New("refresh token invalid")
)

type AccountRepository interface {
	FindByLogin(ctx context.Context, login string) (Account, error)
	FindByID(ctx context.Context, accountID string) (Account, error)
}

type DeviceRepository interface {
	FindByID(ctx context.Context, deviceID string) (Device, error)
	ListByAccount(ctx context.Context, accountID string) ([]Device, error)
	Revoke(ctx context.Context, accountID, deviceID string) error
}

type ChallengeRepository interface {
	Create(ctx context.Context, challenge LoginChallenge) error
	AcquirePasswordAttempt(ctx context.Context, challengeID string, now time.Time) (LoginChallenge, error)
	VerifyRegisterDeviceAndCreateAuthorizationCode(ctx context.Context, challengeID string, now time.Time, code AuthorizationCode) error
}

type SessionRepository interface {
	ExchangeAuthorizationCode(
		ctx context.Context,
		codeHash []byte,
		deviceID string,
		now time.Time,
		session Session,
		refreshToken RefreshToken,
		accessExpiresAt time.Time,
	) (AuthorizationCode, Session, RefreshToken, error)
	RotateRefreshToken(
		ctx context.Context,
		currentTokenHash []byte,
		deviceID string,
		now time.Time,
		replacement RefreshToken,
		accessExpiresAt time.Time,
	) (Session, RefreshToken, error)
	Revoke(ctx context.Context, sessionID string) error
	RevokeByDevice(ctx context.Context, accountID, deviceID string) error
}

type PasswordVerifier interface {
	VerifyPassword(encodedHash, password string) error
}

type TokenHasher interface {
	HashToken(token string) []byte
}

type CredentialGenerator interface {
	NewOpaqueCredential(prefix string) (string, error)
}

type IDGenerator interface {
	NewID(prefix string) (string, error)
}

type AccessTokenIssuer interface {
	IssueAccessToken(accountID, deviceID, sessionID string, expiresAt time.Time) (string, error)
}
