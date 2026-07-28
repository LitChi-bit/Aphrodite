package auth

import "time"

type AccountStatus string

const (
	AccountStatusActive   AccountStatus = "active"
	AccountStatusDisabled AccountStatus = "disabled"
)

type Account struct {
	ID           string
	Username     string
	Email        string
	DisplayName  string
	PasswordHash string
	Status       AccountStatus
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

type Device struct {
	ID                string
	AccountID         string
	Name              string
	Platform          string
	IdentityPublicKey []byte
	LastSeenAt        *time.Time
	RevokedAt         *time.Time
	CreatedAt         time.Time
	UpdatedAt         time.Time
}

type LoginChallenge struct {
	ID                string
	AccountID         string
	DeviceID          string
	DeviceName        string
	DevicePlatform    string
	IdentityPublicKey []byte
	AttemptCount      int
	VerifiedAt        *time.Time
	ConsumedAt        *time.Time
	ExpiresAt         time.Time
	CreatedAt         time.Time
}

type AuthorizationCode struct {
	ID          string
	ChallengeID string
	AccountID   string
	DeviceID    string
	CodeHash    []byte
	ConsumedAt  *time.Time
	ExpiresAt   time.Time
	CreatedAt   time.Time
}

type Session struct {
	ID        string
	AccountID string
	DeviceID  string
	RevokedAt *time.Time
	ExpiresAt time.Time
	CreatedAt time.Time
	UpdatedAt time.Time
}

type RefreshToken struct {
	ID         string
	SessionID  string
	TokenHash  []byte
	ReplacedBy *string
	RotatedAt  *time.Time
	RevokedAt  *time.Time
	ExpiresAt  time.Time
	CreatedAt  time.Time
}

func (device Device) IsRevoked() bool {
	return device.RevokedAt != nil
}

func (challenge LoginChallenge) IsUsable(now time.Time) bool {
	return challenge.VerifiedAt == nil &&
		challenge.ConsumedAt == nil &&
		challenge.AttemptCount < 5 &&
		now.Before(challenge.ExpiresAt)
}

func (code AuthorizationCode) IsUsable(now time.Time) bool {
	return code.ConsumedAt == nil && now.Before(code.ExpiresAt)
}

func (session Session) IsActive(now time.Time) bool {
	return session.RevokedAt == nil && now.Before(session.ExpiresAt)
}

func (token RefreshToken) IsActive(now time.Time) bool {
	return token.RevokedAt == nil && token.ReplacedBy == nil && now.Before(token.ExpiresAt)
}
