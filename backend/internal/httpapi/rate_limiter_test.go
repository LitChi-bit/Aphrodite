package httpapi

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestFixedWindowRateLimiterScopesKeysIndependently(t *testing.T) {
	limiter := newFixedWindowRateLimiter(2, time.Minute)
	now := time.Date(2026, 7, 28, 3, 0, 0, 0, time.UTC)

	for attempt := 0; attempt < 2; attempt++ {
		if allowed, _ := limiter.Allow("challenge", "client-a", now); !allowed {
			t.Fatalf("attempt %d should be allowed", attempt)
		}
	}
	if allowed, retryAfter := limiter.Allow("challenge", "client-a", now); allowed || retryAfter <= 0 {
		t.Fatalf("third request allowed=%t retry_after=%v", allowed, retryAfter)
	}
	if allowed, _ := limiter.Allow("token", "client-a", now); !allowed {
		t.Fatal("different limiter scope must be independent")
	}
	if allowed, _ := limiter.Allow("challenge", "client-b", now); !allowed {
		t.Fatal("different client key must be independent")
	}
}

func TestServerAppliesInjectedLimitersToAuthenticationRoutes(t *testing.T) {
	limiter := &denyRateLimiter{}
	server := NewServer(
		discardLogger(),
		WithAuthService(&stubAuthService{}),
		WithAuthRateLimiters(limiter, limiter),
	)

	for _, path := range []string{
		"/v1/auth/challenges",
		"/v1/auth/challenges/challenge-example/verify",
		"/v1/auth/token",
		"/v1/auth/logout",
	} {
		response := performJSONRequest(server.Handler(), http.MethodPost, path, `{}`)
		if response.Code != http.StatusTooManyRequests {
			t.Fatalf("%s status = %d", path, response.Code)
		}
		if response.Header().Get("Retry-After") == "" {
			t.Fatalf("%s must include Retry-After", path)
		}
	}
}

type denyRateLimiter struct{}

func (denyRateLimiter) Allow(string, string, time.Time) (bool, time.Duration) {
	return false, time.Second
}

func TestFixedWindowRateLimiterPrunesExpiredEntries(t *testing.T) {
	limiter := newFixedWindowRateLimiter(1, time.Minute)
	startedAt := time.Date(2026, 7, 28, 3, 0, 0, 0, time.UTC)
	limiter.Allow("challenge", "expired-client", startedAt)
	limiter.Allow("challenge", "active-client", startedAt.Add(2*time.Minute))

	if _, exists := limiter.windows["challenge\x00expired-client"]; exists {
		t.Fatal("expired client window must be pruned")
	}
	if _, exists := limiter.windows["challenge\x00active-client"]; !exists {
		t.Fatal("current client window must remain")
	}
}

func TestRateLimitReturns429WithoutListening(t *testing.T) {
	limiter := newFixedWindowRateLimiter(1, time.Minute)
	handler := rateLimit(limiter, "auth_token", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	})

	first := httptest.NewRecorder()
	handler(first, httptest.NewRequest(http.MethodPost, "/v1/auth/token", nil))
	if first.Code != http.StatusNoContent {
		t.Fatalf("first status = %d", first.Code)
	}
	second := httptest.NewRecorder()
	handler(second, httptest.NewRequest(http.MethodPost, "/v1/auth/token", nil))
	if second.Code != http.StatusTooManyRequests {
		t.Fatalf("second status = %d", second.Code)
	}
	if second.Header().Get("Retry-After") == "" {
		t.Fatal("rate limited response must include Retry-After")
	}
}
