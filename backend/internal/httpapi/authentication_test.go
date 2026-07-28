package httpapi

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"aphrodite/backend/internal/auth"
)

func TestRequireAccessTokenRejectsMissingMalformedAndInvalidCredentials(t *testing.T) {
	authenticator := &stubAccessTokenAuthenticator{err: auth.ErrAccessTokenInvalid}
	handler := withRequestID(requireAccessToken(authenticator, stubAccessTokenVerifier{}, func(http.ResponseWriter, *http.Request) {
		t.Fatal("next handler must not run")
	}))

	for _, header := range []string{"", "Basic access-example", "Bearer", "Bearer one two", "Bearer access-example"} {
		request := httptest.NewRequest(http.MethodGet, "/v1/protected", nil)
		if header != "" {
			request.Header.Set("Authorization", header)
		}
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		assertErrorResponse(t, response, http.StatusUnauthorized, "invalid_credentials")
	}
}

func TestRequireAccessTokenPassesAuthenticatedSubject(t *testing.T) {
	claims := auth.AccessTokenClaims{
		AccountID: "account-example", DeviceID: "device-example", SessionID: "session-example",
		IssuedAt: time.Date(2026, 7, 28, 4, 0, 0, 0, time.UTC), ExpiresAt: time.Date(2026, 7, 28, 4, 15, 0, 0, time.UTC),
	}
	authenticator := &stubAccessTokenAuthenticator{claims: claims}
	handler := requireAccessToken(authenticator, stubAccessTokenVerifier{}, func(w http.ResponseWriter, r *http.Request) {
		subject, err := authenticatedSubjectFromContext(r.Context())
		if err != nil {
			t.Fatalf("authenticatedSubjectFromContext() error = %v", err)
		}
		if subject.AccountID != claims.AccountID || subject.DeviceID != claims.DeviceID || subject.SessionID != claims.SessionID {
			t.Fatalf("unexpected subject: %#v", subject)
		}
		w.WriteHeader(http.StatusNoContent)
	})
	request := httptest.NewRequest(http.MethodGet, "/v1/protected", nil)
	request.Header.Set("Authorization", "bearer access-example")
	response := httptest.NewRecorder()
	handler(response, request)

	if response.Code != http.StatusNoContent {
		t.Fatalf("status = %d", response.Code)
	}
	if authenticator.token != "access-example" {
		t.Fatalf("token = %q", authenticator.token)
	}
}

func TestAuthenticatedSubjectFromContextRejectsMissingSubject(t *testing.T) {
	if _, err := authenticatedSubjectFromContext(context.Background()); err == nil {
		t.Fatal("missing subject must be rejected")
	}
}

type stubAccessTokenAuthenticator struct {
	claims auth.AccessTokenClaims
	err    error
	token  string
}

func (authenticator *stubAccessTokenAuthenticator) AuthenticateAccessToken(_ context.Context, _ auth.AccessTokenVerifier, token string) (auth.AccessTokenClaims, error) {
	authenticator.token = token
	return authenticator.claims, authenticator.err
}

type stubAccessTokenVerifier struct{}

func (stubAccessTokenVerifier) VerifyAccessToken(string) (auth.AccessTokenClaims, error) {
	return auth.AccessTokenClaims{}, errors.New("not called by stub authenticator")
}
