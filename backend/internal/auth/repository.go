package auth

import (
	"context"
	"errors"
)

var (
	ErrAccountNotFound     = errors.New("account not found")
	ErrDeviceNotFound      = errors.New("device not found")
	ErrChallengeNotFound   = errors.New("login challenge not found")
	ErrSessionNotFound     = errors.New("session not found")
	ErrRefreshTokenInvalid = errors.New("refresh token invalid")
)

type AccountRepository interface {
	FindByLogin(ctx context.Context, login string) (Account, error)
	FindByID(ctx context.Context, accountID string) (Account, error)
}

type DeviceRepository interface {
	Upsert(ctx context.Context, device Device) error
	FindByID(ctx context.Context, deviceID string) (Device, error)
	ListByAccount(ctx context.Context, accountID string) ([]Device, error)
	Revoke(ctx context.Context, accountID, deviceID string) error
}

type ChallengeRepository interface {
	Create(ctx context.Context, challenge LoginChallenge) error
	FindByID(ctx context.Context, challengeID string) (LoginChallenge, error)
	RecordFailedAttempt(ctx context.Context, challengeID string) error
	MarkVerified(ctx context.Context, challengeID string) error
	Consume(ctx context.Context, challengeID string) error
}

type SessionRepository interface {
	Create(ctx context.Context, session Session, refreshToken RefreshToken) error
	FindByRefreshTokenHash(ctx context.Context, tokenHash []byte) (Session, RefreshToken, error)
	RotateRefreshToken(ctx context.Context, currentTokenID string, replacement RefreshToken) error
	Revoke(ctx context.Context, sessionID string) error
	RevokeByDevice(ctx context.Context, accountID, deviceID string) error
}

type PasswordVerifier interface {
	VerifyPassword(encodedHash, password string) error
}

type TokenHasher interface {
	HashToken(token string) []byte
}
