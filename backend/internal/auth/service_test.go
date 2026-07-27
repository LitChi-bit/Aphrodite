package auth

import (
	"bytes"
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"testing"
	"time"
)

func TestAuthenticationFlowAndRefreshRotation(t *testing.T) {
	fixture := newServiceFixture(t)
	ctx := context.Background()

	challenge, err := fixture.service.CreateChallenge(ctx, CreateChallengeInput{
		Login: "example-user", DeviceID: "device-example", DeviceName: "Example device",
		Platform: "android", IdentityPublicKey: []byte("example-public-key"),
	})
	if err != nil {
		t.Fatalf("CreateChallenge() error = %v", err)
	}
	authorization, err := fixture.service.VerifyPassword(ctx, VerifyPasswordInput{
		ChallengeID: challenge.ChallengeID, Password: "example-password",
	})
	if err != nil {
		t.Fatalf("VerifyPassword() error = %v", err)
	}
	if fixture.devices.items["device-example"].ID != "device-example" {
		t.Fatal("first-time device must be registered atomically on password success")
	}
	pair, err := fixture.service.ExchangeAuthorizationCode(ctx, authorization.AuthorizationCode, "device-example")
	if err != nil {
		t.Fatalf("ExchangeAuthorizationCode() error = %v", err)
	}
	if pair.AccessToken == "" || pair.RefreshToken == "" {
		t.Fatal("token pair must contain both credentials")
	}
	if _, err := fixture.service.ExchangeAuthorizationCode(ctx, authorization.AuthorizationCode, "device-example"); !errors.Is(err, ErrAuthorizationCodeInvalid) {
		t.Fatalf("authorization code reuse error = %v", err)
	}

	replacement, err := fixture.service.Refresh(ctx, pair.RefreshToken, "device-example")
	if err != nil {
		t.Fatalf("Refresh() error = %v", err)
	}
	if replacement.RefreshToken == pair.RefreshToken {
		t.Fatal("refresh token must rotate")
	}
	if _, err := fixture.service.Refresh(ctx, pair.RefreshToken, "device-example"); !errors.Is(err, ErrRefreshTokenInvalid) {
		t.Fatalf("old refresh token reuse error = %v", err)
	}
	if !fixture.sessions.isRevoked(fixture.sessions.onlySessionID()) {
		t.Fatal("refresh token replay must revoke the session")
	}
}

func TestExistingDevicePublicKeyCannotBeReplaced(t *testing.T) {
	fixture := newServiceFixture(t)
	ctx := context.Background()
	input := CreateChallengeInput{Login: "example-user", DeviceID: "device-example", DeviceName: "Example device", Platform: "android", IdentityPublicKey: []byte("example-public-key")}
	// Register the device first by completing a full auth flow
	fixture.issuePair(t)
	// Now attempt to create another challenge with a different public key
	input.IdentityPublicKey = []byte("different-example-public-key")
	if _, err := fixture.service.CreateChallenge(ctx, input); !errors.Is(err, ErrCredentialMismatch) {
		t.Fatalf("public key replacement error = %v", err)
	}
}

func TestInvalidPasswordRecordsAttemptAndLocksChallenge(t *testing.T) {
	fixture := newServiceFixture(t)
	ctx := context.Background()
	challenge, err := fixture.service.CreateChallenge(ctx, CreateChallengeInput{
		Login: "example-user", DeviceID: "device-example", DeviceName: "Example device",
		Platform: "android", IdentityPublicKey: []byte("example-public-key"),
	})
	if err != nil {
		t.Fatalf("CreateChallenge() error = %v", err)
	}

	for attempt := 0; attempt < 5; attempt++ {
		_, err = fixture.service.VerifyPassword(ctx, VerifyPasswordInput{
			ChallengeID: challenge.ChallengeID, Password: "wrong-example-password",
		})
		if !errors.Is(err, ErrInvalidCredentials) {
			t.Fatalf("attempt %d error = %v", attempt, err)
		}
	}
	_, err = fixture.service.VerifyPassword(ctx, VerifyPasswordInput{
		ChallengeID: challenge.ChallengeID, Password: "example-password",
	})
	if !errors.Is(err, ErrChallengeLocked) {
		t.Fatalf("locked challenge error = %v", err)
	}
}

func TestRevokedDeviceCannotRefresh(t *testing.T) {
	fixture := newServiceFixture(t)
	ctx := context.Background()
	pair := fixture.issuePair(t)

	if err := fixture.service.RevokeDevice(ctx, "account-example", "device-example"); err != nil {
		t.Fatalf("RevokeDevice() error = %v", err)
	}
	if _, err := fixture.service.Refresh(ctx, pair.RefreshToken, "device-example"); !errors.Is(err, ErrRefreshTokenInvalid) {
		t.Fatalf("refresh after revocation error = %v", err)
	}
	if !fixture.devices.items["device-example"].IsRevoked() {
		t.Fatal("device must be marked revoked")
	}
}

type serviceFixture struct {
	service    *Service
	devices    *memoryDeviceRepository
	sessions   *memorySessionRepository
	challenges *memoryChallengeRepository
}

func newServiceFixture(t *testing.T) serviceFixture {
	t.Helper()
	now := time.Date(2026, 7, 27, 8, 0, 0, 0, time.UTC)
	accounts := &memoryAccountRepository{account: Account{
		ID: "account-example", Username: "example-user", Email: "user@example.com",
		DisplayName: "Example user", PasswordHash: "hash-example-password", Status: AccountStatusActive,
	}}
	devices := &memoryDeviceRepository{items: map[string]Device{}}
	sharedCodes := map[string]AuthorizationCode{}
	challenges := &memoryChallengeRepository{items: map[string]LoginChallenge{}, codes: sharedCodes, devices: devices}
	sessions := &memorySessionRepository{sessions: map[string]Session{}, tokens: map[string]RefreshToken{}, codes: sharedCodes, devices: devices}
	sequence := &sequenceGenerator{}
	service, err := NewService(Dependencies{
		Accounts: accounts, Devices: devices, Challenges: challenges,
		Sessions: sessions, Passwords: exactPasswordVerifier{}, Hasher: sha256TokenHasher{},
		Credentials: sequence, IDs: sequence, AccessTokens: sequenceAccessTokenIssuer{sequence},
		Now: func() time.Time { return now },
	})
	if err != nil {
		t.Fatalf("NewService() error = %v", err)
	}
	return serviceFixture{service: service, devices: devices, sessions: sessions, challenges: challenges}
}

func (fixture serviceFixture) issuePair(t *testing.T) TokenPair {
	t.Helper()
	ctx := context.Background()
	challenge, err := fixture.service.CreateChallenge(ctx, CreateChallengeInput{
		Login: "example-user", DeviceID: "device-example", DeviceName: "Example device",
		Platform: "android", IdentityPublicKey: []byte("example-public-key"),
	})
	if err != nil { t.Fatal(err) }
	authorization, err := fixture.service.VerifyPassword(ctx, VerifyPasswordInput{ChallengeID: challenge.ChallengeID, Password: "example-password"})
	if err != nil { t.Fatal(err) }
	pair, err := fixture.service.ExchangeAuthorizationCode(ctx, authorization.AuthorizationCode, "device-example")
	if err != nil { t.Fatal(err) }
	return pair
}

type memoryAccountRepository struct{ account Account }
func (repo *memoryAccountRepository) FindByLogin(_ context.Context, login string) (Account, error) {
	if login == repo.account.Username || login == repo.account.Email { return repo.account, nil }
	return Account{}, ErrAccountNotFound
}
func (repo *memoryAccountRepository) FindByID(_ context.Context, id string) (Account, error) {
	if id == repo.account.ID { return repo.account, nil }
	return Account{}, ErrAccountNotFound
}

type memoryDeviceRepository struct{ items map[string]Device }
func (repo *memoryDeviceRepository) FindByID(_ context.Context, id string) (Device, error) { device, ok := repo.items[id]; if !ok { return Device{}, ErrDeviceNotFound }; return device, nil }
func (repo *memoryDeviceRepository) ListByAccount(_ context.Context, accountID string) ([]Device, error) { var result []Device; for _, device := range repo.items { if device.AccountID == accountID { result = append(result, device) } }; return result, nil }
func (repo *memoryDeviceRepository) Revoke(_ context.Context, accountID, deviceID string) error { device, ok := repo.items[deviceID]; if !ok || device.AccountID != accountID { return ErrDeviceNotFound }; now := time.Now().UTC(); device.RevokedAt = &now; repo.items[deviceID] = device; return nil }
func (repo *memoryDeviceRepository) upsertDevice(id, accountID, name, platform string, pubkey []byte, createdAt, now time.Time) { device := Device{ID: id, AccountID: accountID, Name: name, Platform: platform, IdentityPublicKey: append([]byte(nil), pubkey...), CreatedAt: createdAt, UpdatedAt: now}; repo.items[id] = device }

type memoryChallengeRepository struct{ items map[string]LoginChallenge; codes map[string]AuthorizationCode; devices *memoryDeviceRepository }
func (repo *memoryChallengeRepository) Create(_ context.Context, challenge LoginChallenge) error { repo.items[challenge.ID] = challenge; return nil }
func (repo *memoryChallengeRepository) AcquirePasswordAttempt(_ context.Context, id string, now time.Time) (LoginChallenge, error) { challenge, ok := repo.items[id]; if !ok || challenge.VerifiedAt != nil || challenge.ConsumedAt != nil || !now.Before(challenge.ExpiresAt) { return LoginChallenge{}, ErrChallengeExpired }; if challenge.AttemptCount >= 5 { return LoginChallenge{}, ErrChallengeLocked }; challenge.AttemptCount++; repo.items[id] = challenge; return challenge, nil }
func (repo *memoryChallengeRepository) VerifyRegisterDeviceAndCreateAuthorizationCode(_ context.Context, id string, now time.Time, code AuthorizationCode) error { challenge, ok := repo.items[id]; if !ok || challenge.VerifiedAt != nil || challenge.ConsumedAt != nil || !now.Before(challenge.ExpiresAt) || challenge.AttemptCount > 5 || code.AccountID != challenge.AccountID || code.DeviceID != challenge.DeviceID { return ErrChallengeExpired }
	// Atomically register device: idempotent upsert; reject if pubkey differs.
	if existing, findErr := repo.devices.FindByID(nil, challenge.DeviceID); findErr == nil {
		_ = existing // already registered, pubkey was verified during CreateChallenge
	} else {
		repo.devices.upsertDevice(challenge.DeviceID, challenge.AccountID, challenge.DeviceName, challenge.DevicePlatform, challenge.IdentityPublicKey, challenge.CreatedAt, now)
	}
	challenge.VerifiedAt = &now; repo.items[id] = challenge; repo.codes[string(code.CodeHash)] = code; return nil }

type memorySessionRepository struct{ sessions map[string]Session; tokens map[string]RefreshToken; codes map[string]AuthorizationCode; devices *memoryDeviceRepository }
func (repo *memorySessionRepository) ExchangeAuthorizationCode(_ context.Context, hash []byte, deviceID string, now time.Time, session Session, token RefreshToken, accessExpiresAt time.Time) (AuthorizationCode, Session, RefreshToken, error) { code, ok := repo.codes[string(hash)]; if !ok || !code.IsUsable(now) || code.DeviceID != deviceID || !accessExpiresAt.After(now) { return AuthorizationCode{}, Session{}, RefreshToken{}, ErrAuthorizationCodeInvalid }; device, deviceErr := repo.devices.FindByID(nil, deviceID); if deviceErr != nil || device.AccountID != code.AccountID || device.IsRevoked() { return AuthorizationCode{}, Session{}, RefreshToken{}, ErrDeviceRevoked }; code.ConsumedAt = &now; repo.codes[string(hash)] = code; session.AccountID = code.AccountID; token.SessionID = session.ID; repo.sessions[session.ID] = session; repo.tokens[string(token.TokenHash)] = token; return code, session, token, nil }
func (repo *memorySessionRepository) RotateRefreshToken(_ context.Context, currentHash []byte, deviceID string, now time.Time, replacement RefreshToken, accessExpiresAt time.Time) (Session, RefreshToken, error) { token, ok := repo.tokens[string(currentHash)]; if !ok { return Session{}, RefreshToken{}, ErrRefreshTokenInvalid }; session, ok := repo.sessions[token.SessionID]; if !ok || !token.IsActive(now) || !session.IsActive(now) || session.DeviceID != deviceID || !accessExpiresAt.After(now) { if ok { revoked := now; session.RevokedAt = &revoked; repo.sessions[session.ID] = session }; return Session{}, RefreshToken{}, ErrRefreshTokenInvalid }
	// Check device revocation atomically within rotation.
	if device, deviceErr := repo.devices.FindByID(nil, deviceID); deviceErr != nil || device.AccountID != session.AccountID || device.IsRevoked() { revoked := now; session.RevokedAt = &revoked; repo.sessions[session.ID] = session; return Session{}, RefreshToken{}, ErrRefreshTokenInvalid }
	token.ReplacedBy = &replacement.ID; token.RotatedAt = &now; repo.tokens[string(currentHash)] = token; replacement.SessionID = session.ID; if replacement.ExpiresAt.After(session.ExpiresAt) { replacement.ExpiresAt = session.ExpiresAt }; repo.tokens[string(replacement.TokenHash)] = replacement; return session, replacement, nil }
func (repo *memorySessionRepository) Revoke(_ context.Context, sessionID string) error { session, ok := repo.sessions[sessionID]; if !ok { return ErrSessionNotFound }; now := time.Now().UTC(); session.RevokedAt = &now; repo.sessions[sessionID] = session; return nil }
func (repo *memorySessionRepository) RevokeByDevice(_ context.Context, accountID, deviceID string) error { for id, session := range repo.sessions { if session.AccountID == accountID && session.DeviceID == deviceID { now := time.Now().UTC(); session.RevokedAt = &now; repo.sessions[id] = session } }; return nil }
func (repo *memorySessionRepository) onlySessionID() string { for id := range repo.sessions { return id }; return "" }
func (repo *memorySessionRepository) isRevoked(id string) bool { return repo.sessions[id].RevokedAt != nil }

type exactPasswordVerifier struct{}
func (exactPasswordVerifier) VerifyPassword(encodedHash, password string) error { if encodedHash != "hash-"+password { return ErrInvalidCredentials }; return nil }
type sha256TokenHasher struct{}
func (sha256TokenHasher) HashToken(token string) []byte { sum := sha256.Sum256([]byte(token)); return sum[:] }
type sequenceGenerator struct{ value int }
func (generator *sequenceGenerator) next(prefix string) string { generator.value++; return fmt.Sprintf("%s-example-%d", prefix, generator.value) }
func (generator *sequenceGenerator) NewOpaqueCredential(prefix string) (string, error) { return generator.next(prefix), nil }
func (generator *sequenceGenerator) NewID(prefix string) (string, error) { return generator.next(prefix), nil }
type sequenceAccessTokenIssuer struct{ generator *sequenceGenerator }
func (issuer sequenceAccessTokenIssuer) IssueAccessToken(accountID, deviceID, sessionID string, expiresAt time.Time) (string, error) { if len(bytes.TrimSpace([]byte(accountID))) == 0 || deviceID == "" || sessionID == "" || expiresAt.IsZero() { return "", errors.New("invalid claims") }; return issuer.generator.next("access"), nil }
