package auth

import (
	"testing"
	"time"
)

func TestLoginChallengeIsUsable(t *testing.T) {
	now := time.Date(2026, 7, 27, 8, 0, 0, 0, time.UTC)
	challenge := LoginChallenge{ExpiresAt: now.Add(time.Minute)}

	if !challenge.IsUsable(now) {
		t.Fatal("fresh challenge should be usable")
	}

	challenge.AttemptCount = 5
	if challenge.IsUsable(now) {
		t.Fatal("challenge at attempt limit must not be usable")
	}
}

func TestRefreshTokenIsInactiveAfterRotation(t *testing.T) {
	now := time.Date(2026, 7, 27, 8, 0, 0, 0, time.UTC)
	replacementID := "refresh-example-new"
	token := RefreshToken{
		ExpiresAt:  now.Add(time.Hour),
		ReplacedBy: &replacementID,
	}

	if token.IsActive(now) {
		t.Fatal("replaced refresh token must not remain active")
	}
}

func TestSessionExpiresAtBoundary(t *testing.T) {
	now := time.Date(2026, 7, 27, 8, 0, 0, 0, time.UTC)
	session := Session{ExpiresAt: now}

	if session.IsActive(now) {
		t.Fatal("session must be inactive at its expiry instant")
	}
}
