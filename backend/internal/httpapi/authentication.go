package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"aphrodite/backend/internal/auth"
)

type AccessTokenAuthenticator interface {
	AuthenticateAccessToken(ctx context.Context, verifier auth.AccessTokenVerifier, token string) (auth.AccessTokenClaims, error)
}

type authenticatedSubject struct {
	AccountID string
	DeviceID  string
	SessionID string
}

type authenticatedSubjectContextKey struct{}

func requireAccessToken(authenticator AccessTokenAuthenticator, verifier auth.AccessTokenVerifier, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token, ok := bearerToken(r.Header.Get("Authorization"))
		if !ok || authenticator == nil || verifier == nil {
			writeError(w, r, http.StatusUnauthorized, "invalid_credentials", "invalid credentials")
			return
		}
		claims, err := authenticator.AuthenticateAccessToken(r.Context(), verifier, token)
		if err != nil {
			writeError(w, r, http.StatusUnauthorized, "invalid_credentials", "invalid credentials")
			return
		}
		subject := authenticatedSubject{
			AccountID: claims.AccountID,
			DeviceID:  claims.DeviceID,
			SessionID: claims.SessionID,
		}
		next(w, r.WithContext(context.WithValue(r.Context(), authenticatedSubjectContextKey{}, subject)))
	}
}

func bearerToken(header string) (string, bool) {
	parts := strings.Fields(header)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") || strings.TrimSpace(parts[1]) == "" {
		return "", false
	}
	return parts[1], true
}

func authenticatedSubjectFromContext(ctx context.Context) (authenticatedSubject, error) {
	subject, ok := ctx.Value(authenticatedSubjectContextKey{}).(authenticatedSubject)
	if !ok || subject.AccountID == "" || subject.DeviceID == "" || subject.SessionID == "" {
		return authenticatedSubject{}, errors.New("authenticated subject missing")
	}
	return subject, nil
}
