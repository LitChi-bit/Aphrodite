package auth

import (
	"context"
	"crypto/subtle"
	"errors"
	"fmt"
	"strings"
	"time"
)

var (
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrAccountDisabled    = errors.New("account disabled")
	ErrDeviceRevoked      = errors.New("device revoked")
	ErrChallengeExpired   = errors.New("login challenge expired")
	ErrChallengeLocked    = errors.New("login challenge locked")
	ErrCredentialMismatch = errors.New("credential does not belong to device")
)

type Clock func() time.Time

type Service struct {
	accounts     AccountRepository
	devices      DeviceRepository
	challenges   ChallengeRepository
	sessions     SessionRepository
	passwords    PasswordVerifier
	hasher       TokenHasher
	credentials  CredentialGenerator
	ids          IDGenerator
	accessTokens AccessTokenIssuer
	now          Clock
	challengeTTL time.Duration
	codeTTL      time.Duration
	sessionTTL   time.Duration
	refreshTTL   time.Duration
}

type Dependencies struct {
	Accounts     AccountRepository
	Devices      DeviceRepository
	Challenges   ChallengeRepository
	Sessions     SessionRepository
	Passwords    PasswordVerifier
	Hasher       TokenHasher
	Credentials  CredentialGenerator
	IDs          IDGenerator
	AccessTokens AccessTokenIssuer
	Now          Clock
}

func NewService(dependencies Dependencies) (*Service, error) {
	if dependencies.Accounts == nil || dependencies.Devices == nil ||
		dependencies.Challenges == nil || dependencies.Sessions == nil ||
		dependencies.Passwords == nil ||
		dependencies.Hasher == nil || dependencies.Credentials == nil ||
		dependencies.IDs == nil || dependencies.AccessTokens == nil {
		return nil, errors.New("auth service dependencies are incomplete")
	}
	if dependencies.Now == nil {
		dependencies.Now = time.Now
	}
	return &Service{
		accounts: dependencies.Accounts, devices: dependencies.Devices,
		challenges: dependencies.Challenges,
		sessions:   dependencies.Sessions, passwords: dependencies.Passwords,
		hasher: dependencies.Hasher, credentials: dependencies.Credentials,
		ids: dependencies.IDs, accessTokens: dependencies.AccessTokens,
		now: dependencies.Now, challengeTTL: 5 * time.Minute,
		codeTTL: time.Minute, sessionTTL: 30 * 24 * time.Hour,
		refreshTTL: 30 * 24 * time.Hour,
	}, nil
}

type CreateChallengeInput struct {
	Login             string
	DeviceID          string
	DeviceName        string
	Platform          string
	IdentityPublicKey []byte
}

type ChallengeResult struct {
	ChallengeID string
	ExpiresAt   time.Time
}

func (s *Service) CreateChallenge(ctx context.Context, input CreateChallengeInput) (ChallengeResult, error) {
	login := strings.TrimSpace(strings.ToLower(input.Login))
	if login == "" || input.DeviceID == "" || input.DeviceName == "" ||
		input.Platform == "" || len(input.IdentityPublicKey) == 0 {
		return ChallengeResult{}, ErrInvalidCredentials
	}
	account, err := s.accounts.FindByLogin(ctx, login)
	if err != nil {
		return ChallengeResult{}, ErrInvalidCredentials
	}
	if account.Status != AccountStatusActive {
		return ChallengeResult{}, ErrAccountDisabled
	}
	now := s.now().UTC()
	if existing, findErr := s.devices.FindByID(ctx, input.DeviceID); findErr == nil {
		if existing.AccountID != account.ID {
			return ChallengeResult{}, ErrCredentialMismatch
		}
		if existing.IsRevoked() {
			return ChallengeResult{}, ErrDeviceRevoked
		}
		if subtle.ConstantTimeCompare(existing.IdentityPublicKey, input.IdentityPublicKey) != 1 {
			return ChallengeResult{}, ErrCredentialMismatch
		}
	} else if !errors.Is(findErr, ErrDeviceNotFound) {
		return ChallengeResult{}, fmt.Errorf("find device: %w", findErr)
	}
	challengeID, err := s.ids.NewID("challenge")
	if err != nil {
		return ChallengeResult{}, fmt.Errorf("create challenge id: %w", err)
	}
	challenge := LoginChallenge{
		ID: challengeID, AccountID: account.ID, DeviceID: input.DeviceID,
		DeviceName: input.DeviceName, DevicePlatform: input.Platform,
		IdentityPublicKey: append([]byte(nil), input.IdentityPublicKey...),
		ExpiresAt:         now.Add(s.challengeTTL), CreatedAt: now,
	}
	if err := s.challenges.Create(ctx, challenge); err != nil {
		return ChallengeResult{}, fmt.Errorf("save challenge: %w", err)
	}
	return ChallengeResult{ChallengeID: challenge.ID, ExpiresAt: challenge.ExpiresAt}, nil
}

type VerifyPasswordInput struct {
	ChallengeID string
	Password    string
}

type AuthorizationResult struct {
	AuthorizationCode string
	ExpiresAt         time.Time
}

func (s *Service) VerifyPassword(ctx context.Context, input VerifyPasswordInput) (AuthorizationResult, error) {
	now := s.now().UTC()
	challenge, err := s.challenges.AcquirePasswordAttempt(ctx, input.ChallengeID, now)
	if errors.Is(err, ErrChallengeLocked) {
		return AuthorizationResult{}, ErrChallengeLocked
	}
	if err != nil {
		return AuthorizationResult{}, ErrChallengeExpired
	}
	account, err := s.accounts.FindByID(ctx, challenge.AccountID)
	if err != nil || account.Status != AccountStatusActive {
		return AuthorizationResult{}, ErrInvalidCredentials
	}
	if err := s.passwords.VerifyPassword(account.PasswordHash, input.Password); err != nil {
		return AuthorizationResult{}, ErrInvalidCredentials
	}
	plainCode, err := s.credentials.NewOpaqueCredential("authorization")
	if err != nil {
		return AuthorizationResult{}, fmt.Errorf("create authorization code: %w", err)
	}
	codeID, err := s.ids.NewID("authorization")
	if err != nil {
		return AuthorizationResult{}, fmt.Errorf("create authorization id: %w", err)
	}
	code := AuthorizationCode{
		ID: codeID, ChallengeID: challenge.ID, AccountID: account.ID, DeviceID: challenge.DeviceID,
		CodeHash: s.hasher.HashToken(plainCode), ExpiresAt: now.Add(s.codeTTL), CreatedAt: now,
	}
	if err := s.challenges.VerifyRegisterDeviceAndCreateAuthorizationCode(ctx, challenge.ID, now, code); err != nil {
		return AuthorizationResult{}, fmt.Errorf("verify challenge and save authorization code: %w", err)
	}
	return AuthorizationResult{AuthorizationCode: plainCode, ExpiresAt: code.ExpiresAt}, nil
}

type TokenPair struct {
	AccessToken      string
	RefreshToken     string
	AccessExpiresIn  time.Duration
	RefreshExpiresIn time.Duration
}

func (s *Service) ExchangeAuthorizationCode(ctx context.Context, plainCode, deviceID string) (TokenPair, error) {
	now := s.now().UTC()
	sessionID, err := s.ids.NewID("session")
	if err != nil {
		return TokenPair{}, err
	}
	refreshID, err := s.ids.NewID("refresh")
	if err != nil {
		return TokenPair{}, err
	}
	plainRefresh, err := s.credentials.NewOpaqueCredential("refresh")
	if err != nil {
		return TokenPair{}, err
	}
	session := Session{ID: sessionID, DeviceID: deviceID,
		ExpiresAt: now.Add(s.sessionTTL), CreatedAt: now, UpdatedAt: now}
	refresh := RefreshToken{ID: refreshID, SessionID: sessionID,
		TokenHash: s.hasher.HashToken(plainRefresh), ExpiresAt: now.Add(s.refreshTTL), CreatedAt: now}
	accessExpiry := now.Add(15 * time.Minute)
	code, session, refresh, err := s.sessions.ExchangeAuthorizationCode(
		ctx, s.hasher.HashToken(plainCode), deviceID, now, session, refresh, accessExpiry,
	)
	if err != nil {
		return TokenPair{}, ErrAuthorizationCodeInvalid
	}
	account, err := s.accounts.FindByID(ctx, code.AccountID)
	if err != nil || account.Status != AccountStatusActive {
		if revokeErr := s.sessions.Revoke(ctx, session.ID); revokeErr != nil {
			return TokenPair{}, fmt.Errorf("account disabled and session revoke failed: %w", revokeErr)
		}
		return TokenPair{}, ErrAccountDisabled
	}
	access, err := s.accessTokens.IssueAccessToken(session.AccountID, deviceID, session.ID, accessExpiry)
	if err != nil {
		if revokeErr := s.sessions.Revoke(ctx, session.ID); revokeErr != nil {
			return TokenPair{}, fmt.Errorf("issue access token: %v; session revoke failed: %w", err, revokeErr)
		}
		return TokenPair{}, fmt.Errorf("issue access token: %w", err)
	}
	return TokenPair{AccessToken: access, RefreshToken: plainRefresh,
		AccessExpiresIn: 15 * time.Minute, RefreshExpiresIn: s.refreshTTL}, nil
}

func (s *Service) Refresh(ctx context.Context, plainRefresh, deviceID string) (TokenPair, error) {
	now := s.now().UTC()
	plainReplacement, err := s.credentials.NewOpaqueCredential("refresh")
	if err != nil {
		return TokenPair{}, err
	}
	replacementID, err := s.ids.NewID("refresh")
	if err != nil {
		return TokenPair{}, err
	}
	replacement := RefreshToken{ID: replacementID,
		TokenHash: s.hasher.HashToken(plainReplacement), ExpiresAt: now.Add(s.refreshTTL), CreatedAt: now}
	accessExpiry := now.Add(15 * time.Minute)
	session, replacement, err := s.sessions.RotateRefreshToken(
		ctx, s.hasher.HashToken(plainRefresh), deviceID, now, replacement, accessExpiry,
	)
	if err != nil {
		return TokenPair{}, ErrRefreshTokenInvalid
	}
	device, err := s.devices.FindByID(ctx, deviceID)
	if err != nil || device.AccountID != session.AccountID || device.IsRevoked() {
		if revokeErr := s.sessions.Revoke(ctx, session.ID); revokeErr != nil {
			return TokenPair{}, fmt.Errorf("device revoked and session revoke failed: %w", revokeErr)
		}
		return TokenPair{}, ErrDeviceRevoked
	}
	account, err := s.accounts.FindByID(ctx, session.AccountID)
	if err != nil || account.Status != AccountStatusActive {
		if revokeErr := s.sessions.Revoke(ctx, session.ID); revokeErr != nil {
			return TokenPair{}, fmt.Errorf("account disabled and session revoke failed: %w", revokeErr)
		}
		return TokenPair{}, ErrAccountDisabled
	}
	refreshExpiry := replacement.ExpiresAt
	if session.ExpiresAt.Before(refreshExpiry) {
		refreshExpiry = session.ExpiresAt
	}
	if session.ExpiresAt.Before(accessExpiry) {
		accessExpiry = session.ExpiresAt
	}
	access, err := s.accessTokens.IssueAccessToken(session.AccountID, deviceID, session.ID, accessExpiry)
	if err != nil {
		if revokeErr := s.sessions.Revoke(ctx, session.ID); revokeErr != nil {
			return TokenPair{}, fmt.Errorf("issue access token: %v; session revoke failed: %w", err, revokeErr)
		}
		return TokenPair{}, fmt.Errorf("issue access token: %w", err)
	}
	return TokenPair{AccessToken: access, RefreshToken: plainReplacement,
		AccessExpiresIn: accessExpiry.Sub(now), RefreshExpiresIn: refreshExpiry.Sub(now)}, nil
}

func (s *Service) Logout(ctx context.Context, plainRefresh, deviceID string) error {
	if strings.TrimSpace(plainRefresh) == "" || strings.TrimSpace(deviceID) == "" {
		return ErrRefreshTokenInvalid
	}
	if err := s.sessions.RevokeByRefreshToken(
		ctx, s.hasher.HashToken(plainRefresh), deviceID, s.now().UTC(),
	); err != nil {
		return ErrRefreshTokenInvalid
	}
	return nil
}

func (s *Service) AuthenticateAccessToken(ctx context.Context, verifier AccessTokenVerifier, token string) (AccessTokenClaims, error) {
	if verifier == nil || strings.TrimSpace(token) == "" {
		return AccessTokenClaims{}, ErrAccessTokenInvalid
	}
	claims, err := verifier.VerifyAccessToken(token)
	if err != nil {
		return AccessTokenClaims{}, ErrAccessTokenInvalid
	}
	now := s.now().UTC()
	if _, err := s.sessions.FindActive(ctx, claims.SessionID, claims.AccountID, claims.DeviceID, now); err != nil {
		return AccessTokenClaims{}, ErrAccessTokenInvalid
	}
	device, err := s.devices.FindByID(ctx, claims.DeviceID)
	if err != nil || device.AccountID != claims.AccountID || device.IsRevoked() {
		return AccessTokenClaims{}, ErrAccessTokenInvalid
	}
	account, err := s.accounts.FindByID(ctx, claims.AccountID)
	if err != nil || account.Status != AccountStatusActive {
		return AccessTokenClaims{}, ErrAccessTokenInvalid
	}
	return claims, nil
}

func (s *Service) RevokeDevice(ctx context.Context, accountID, deviceID string) error {
	device, err := s.devices.FindByID(ctx, deviceID)
	if err != nil || subtle.ConstantTimeCompare([]byte(device.AccountID), []byte(accountID)) != 1 {
		return ErrDeviceNotFound
	}
	if err := s.devices.Revoke(ctx, accountID, deviceID); err != nil {
		return err
	}
	return s.sessions.RevokeByDevice(ctx, accountID, deviceID)
}
