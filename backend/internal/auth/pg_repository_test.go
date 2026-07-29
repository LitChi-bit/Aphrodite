package auth

import (
	"context"
	"errors"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TestEqualBytes(t *testing.T) {
	tests := []struct {
		name  string
		left  []byte
		right []byte
		want  bool
	}{
		{name: "equal", left: []byte{1, 2, 3}, right: []byte{1, 2, 3}, want: true},
		{name: "different content", left: []byte{1, 2, 3}, right: []byte{1, 2, 4}, want: false},
		{name: "different lengths", left: []byte{1, 2}, right: []byte{1, 2, 0}, want: false},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := equalBytes(test.left, test.right); got != test.want {
				t.Fatalf("equalBytes() = %v, want %v", got, test.want)
			}
		})
	}
}

func TestMinTime(t *testing.T) {
	earlier := time.Date(2026, 7, 29, 10, 0, 0, 0, time.UTC)
	later := earlier.Add(time.Hour)
	if got := minTime(later, earlier); !got.Equal(earlier) {
		t.Fatalf("minTime() = %v, want %v", got, earlier)
	}
	if got := minTime(earlier, later); !got.Equal(earlier) {
		t.Fatalf("minTime() = %v, want %v", got, earlier)
	}
}

func TestPostgresRepositoryAuthenticationTransactions(t *testing.T) {
	pool := postgresIntegrationPool(t)
	ctx := context.Background()
	truncateAuthTables(t, pool)
	t.Cleanup(func() { truncateAuthTables(t, pool) })

	now := time.Date(2026, 7, 29, 5, 0, 0, 0, time.UTC)
	accountID := "11111111-1111-4111-8111-111111111111"
	deviceID := "22222222-2222-4222-8222-222222222222"
	challengeID := "33333333-3333-4333-8333-333333333333"
	codeID := "44444444-4444-4444-8444-444444444444"
	sessionID := "55555555-5555-4555-8555-555555555555"
	refreshID := "66666666-6666-4666-8666-666666666666"
	replacementID := "77777777-7777-4777-8777-777777777777"
	identityKey := []byte("example-test-identity-public-key")

	if _, err := pool.Exec(ctx, `INSERT INTO accounts (id, username, email, display_name, password_hash, status, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,'active',$6,$6)`, accountID, "integration-user", "integration@example.test", "Integration user", "example-test-password-hash", now); err != nil {
		t.Fatalf("insert account: %v", err)
	}
	repository := NewPostgresRepository(pool)
	challenge := LoginChallenge{
		ID: challengeID, AccountID: accountID, DeviceID: deviceID, DeviceName: "Integration device",
		DevicePlatform: "android", IdentityPublicKey: identityKey, ExpiresAt: now.Add(5 * time.Minute), CreatedAt: now,
	}
	if err := repository.Create(ctx, challenge); err != nil {
		t.Fatalf("Create() error = %v", err)
	}
	acquired, err := repository.AcquirePasswordAttempt(ctx, challengeID, now)
	if err != nil || acquired.AttemptCount != 1 {
		t.Fatalf("AcquirePasswordAttempt() challenge=%#v error=%v", acquired, err)
	}
	codeHash := (SHA256TokenHasher{}).HashToken("authorization-integration-example")
	code := AuthorizationCode{
		ID: codeID, ChallengeID: challengeID, AccountID: accountID, DeviceID: deviceID,
		CodeHash: codeHash, ExpiresAt: now.Add(time.Minute), CreatedAt: now,
	}
	if err := repository.VerifyRegisterDeviceAndCreateAuthorizationCode(ctx, challengeID, now, code); err != nil {
		t.Fatalf("VerifyRegisterDeviceAndCreateAuthorizationCode() error = %v", err)
	}
	device, err := repository.FindByID(ctx, deviceID)
	if err != nil || device.AccountID != accountID || !equalBytes(device.IdentityPublicKey, identityKey) {
		t.Fatalf("FindByID() device=%#v error=%v", device, err)
	}

	refreshHash := (SHA256TokenHasher{}).HashToken("refresh-integration-example")
	session := Session{ID: sessionID, DeviceID: deviceID, ExpiresAt: now.Add(24 * time.Hour), CreatedAt: now, UpdatedAt: now}
	refresh := RefreshToken{ID: refreshID, TokenHash: refreshHash, ExpiresAt: now.Add(24 * time.Hour), CreatedAt: now}
	_, exchangedSession, _, err := repository.ExchangeAuthorizationCode(ctx, codeHash, deviceID, now, session, refresh, now.Add(15*time.Minute))
	if err != nil || exchangedSession.AccountID != accountID {
		t.Fatalf("ExchangeAuthorizationCode() session=%#v error=%v", exchangedSession, err)
	}
	if _, _, _, err := repository.ExchangeAuthorizationCode(ctx, codeHash, deviceID, now, session, refresh, now.Add(15*time.Minute)); !errors.Is(err, ErrAuthorizationCodeInvalid) {
		t.Fatalf("authorization code reuse error = %v", err)
	}

	replacementHash := (SHA256TokenHasher{}).HashToken("replacement-integration-example")
	replacement := RefreshToken{ID: replacementID, TokenHash: replacementHash, ExpiresAt: now.Add(48 * time.Hour), CreatedAt: now}
	rotatedSession, rotated, err := repository.RotateRefreshToken(ctx, refreshHash, deviceID, now.Add(time.Second), replacement, now.Add(15*time.Minute))
	if err != nil || rotatedSession.ID != sessionID || !rotated.ExpiresAt.Equal(session.ExpiresAt) {
		t.Fatalf("RotateRefreshToken() session=%#v token=%#v error=%v", rotatedSession, rotated, err)
	}
	if err := repository.RevokeByRefreshToken(ctx, refreshHash, deviceID, now.Add(2*time.Second)); !errors.Is(err, ErrRefreshTokenInvalid) {
		t.Fatalf("old refresh token logout error = %v", err)
	}
	if _, err := repository.FindActive(ctx, sessionID, accountID, deviceID, now.Add(2*time.Second)); err != nil {
		t.Fatalf("old token logout must not revoke active session: %v", err)
	}
	if err := repository.RevokeByRefreshToken(ctx, replacementHash, deviceID, now.Add(2*time.Second)); err != nil {
		t.Fatalf("RevokeByRefreshToken() error = %v", err)
	}
	if _, err := repository.FindActive(ctx, sessionID, accountID, deviceID, now.Add(2*time.Second)); !errors.Is(err, ErrSessionNotFound) {
		t.Fatalf("revoked session lookup error = %v", err)
	}
}

func postgresIntegrationPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	databaseURL := strings.TrimSpace(os.Getenv("APHRODITE_TEST_DATABASE_URL"))
	if databaseURL == "" {
		t.Skip("requires APHRODITE_TEST_DATABASE_URL; no database connection attempted")
	}
	configuration, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		t.Fatalf("parse APHRODITE_TEST_DATABASE_URL: %v", err)
	}
	if !strings.HasSuffix(strings.ToLower(configuration.ConnConfig.Database), "_test") {
		t.Fatalf("refusing integration test against non-test database %q", configuration.ConnConfig.Database)
	}
	pool, err := pgxpool.NewWithConfig(context.Background(), configuration)
	if err != nil {
		t.Fatalf("create integration pool: %v", err)
	}
	t.Cleanup(pool.Close)
	if err := pool.Ping(context.Background()); err != nil {
		t.Fatalf("ping integration database: %v", err)
	}
	return pool
}

func truncateAuthTables(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	_, err := pool.Exec(context.Background(), `TRUNCATE refresh_tokens, auth_sessions, authorization_codes, login_challenges, devices, accounts CASCADE`)
	if err != nil {
		t.Fatalf("truncate integration database: %v", err)
	}
}
