package httpapi

import (
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"aphrodite/backend/internal/auth"
)

const maxJSONBodyBytes = 64 << 10

type AuthService interface {
	CreateChallenge(ctx context.Context, input auth.CreateChallengeInput) (auth.ChallengeResult, error)
	VerifyPassword(ctx context.Context, input auth.VerifyPasswordInput) (auth.AuthorizationResult, error)
	ExchangeAuthorizationCode(ctx context.Context, code, deviceID string) (auth.TokenPair, error)
	Refresh(ctx context.Context, refreshToken, deviceID string) (auth.TokenPair, error)
	Logout(ctx context.Context, refreshToken, deviceID string) error
}

type authHandler struct {
	service          AuthService
	challengeLimiter RateLimiter
	tokenLimiter     RateLimiter
}

func (handler authHandler) register(mux *http.ServeMux) {
	mux.HandleFunc("POST /v1/auth/challenges", rateLimit(handler.challengeLimiter, "auth_challenge", handler.createChallenge))
	mux.HandleFunc("POST /v1/auth/challenges/{challenge_id}/verify", rateLimit(handler.challengeLimiter, "auth_verify", handler.verifyChallenge))
	mux.HandleFunc("POST /v1/auth/token", rateLimit(handler.tokenLimiter, "auth_token", handler.issueToken))
	mux.HandleFunc("POST /v1/auth/logout", rateLimit(handler.tokenLimiter, "auth_logout", handler.logout))
	mux.HandleFunc("/v1/auth/challenges", methodNotAllowed(http.MethodPost))
	mux.HandleFunc("/v1/auth/challenges/{challenge_id}/verify", methodNotAllowed(http.MethodPost))
	mux.HandleFunc("/v1/auth/token", methodNotAllowed(http.MethodPost))
	mux.HandleFunc("/v1/auth/logout", methodNotAllowed(http.MethodPost))
}

func methodNotAllowed(allowedMethod string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Allow", allowedMethod)
		writeError(w, r, http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed")
	}
}

type createChallengeRequest struct {
	Login             string `json:"login"`
	DeviceName        string `json:"device_name"`
	DeviceID          string `json:"device_id"`
	Platform          string `json:"platform"`
	IdentityPublicKey string `json:"identity_public_key"`
}

type challengeResponse struct {
	ChallengeID string    `json:"challenge_id"`
	ExpiresAt   time.Time `json:"expires_at"`
	Factors     []factor  `json:"factors"`
}

type factor struct {
	Type     string `json:"type"`
	Required bool   `json:"required"`
}

func (handler authHandler) createChallenge(w http.ResponseWriter, r *http.Request) {
	preventCredentialCaching(w)
	var request createChallengeRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeJSONDecodeError(w, r, err)
		return
	}
	publicKey, err := base64.StdEncoding.Strict().DecodeString(request.IdentityPublicKey)
	if err != nil || len(publicKey) != ed25519.PublicKeySize {
		writeError(w, r, http.StatusBadRequest, "invalid_identity_public_key", "identity_public_key must be a base64 Ed25519 public key")
		return
	}
	result, err := handler.service.CreateChallenge(r.Context(), auth.CreateChallengeInput{
		Login: request.Login, DeviceID: request.DeviceID, DeviceName: request.DeviceName,
		Platform: request.Platform, IdentityPublicKey: publicKey,
	})
	if err != nil {
		writeAuthError(w, r, err)
		return
	}
	writeData(w, r, http.StatusCreated, challengeResponse{
		ChallengeID: result.ChallengeID,
		ExpiresAt:   result.ExpiresAt,
		Factors:     []factor{{Type: "password", Required: true}},
	})
}

type verifyChallengeRequest struct {
	Factor string `json:"factor"`
	Value  string `json:"value"`
	Step   string `json:"step"`
}

type verifyChallengeResponse struct {
	Verified          bool      `json:"verified"`
	AuthorizationCode string    `json:"authorization_code"`
	ExpiresAt         time.Time `json:"expires_at"`
}

func (handler authHandler) verifyChallenge(w http.ResponseWriter, r *http.Request) {
	preventCredentialCaching(w)
	var request verifyChallengeRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeJSONDecodeError(w, r, err)
		return
	}
	if request.Factor != "password" || request.Step != "primary" || request.Value == "" {
		writeError(w, r, http.StatusBadRequest, "unsupported_factor", "only the primary password factor is supported")
		return
	}
	result, err := handler.service.VerifyPassword(r.Context(), auth.VerifyPasswordInput{
		ChallengeID: r.PathValue("challenge_id"), Password: request.Value,
	})
	if err != nil {
		writeAuthError(w, r, err)
		return
	}
	writeData(w, r, http.StatusOK, verifyChallengeResponse{
		Verified: true, AuthorizationCode: result.AuthorizationCode, ExpiresAt: result.ExpiresAt,
	})
}

type tokenRequest struct {
	GrantType    string `json:"grant_type"`
	Code         string `json:"code"`
	RefreshToken string `json:"refresh_token"`
	DeviceID     string `json:"device_id"`
}

type tokenResponse struct {
	AccessToken      string `json:"access_token"`
	RefreshToken     string `json:"refresh_token"`
	TokenType        string `json:"token_type"`
	ExpiresIn        int64  `json:"expires_in"`
	RefreshExpiresIn int64  `json:"refresh_expires_in"`
}

type logoutRequest struct {
	RefreshToken string `json:"refresh_token"`
	DeviceID     string `json:"device_id"`
}

func (handler authHandler) logout(w http.ResponseWriter, r *http.Request) {
	preventCredentialCaching(w)
	var request logoutRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeJSONDecodeError(w, r, err)
		return
	}
	if strings.TrimSpace(request.RefreshToken) == "" || strings.TrimSpace(request.DeviceID) == "" {
		writeError(w, r, http.StatusBadRequest, "invalid_request", "refresh_token and device_id are required")
		return
	}
	if err := handler.service.Logout(r.Context(), request.RefreshToken, request.DeviceID); err != nil {
		writeAuthError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (handler authHandler) issueToken(w http.ResponseWriter, r *http.Request) {
	preventCredentialCaching(w)
	var request tokenRequest
	if err := decodeJSON(w, r, &request); err != nil {
		writeJSONDecodeError(w, r, err)
		return
	}
	if strings.TrimSpace(request.DeviceID) == "" {
		writeError(w, r, http.StatusBadRequest, "invalid_request", "device_id is required")
		return
	}
	var (
		pair auth.TokenPair
		err  error
	)
	switch request.GrantType {
	case "authorization_code":
		if request.Code == "" || request.RefreshToken != "" {
			writeError(w, r, http.StatusBadRequest, "invalid_grant", "authorization code grant is malformed")
			return
		}
		pair, err = handler.service.ExchangeAuthorizationCode(r.Context(), request.Code, request.DeviceID)
	case "refresh_token":
		if request.RefreshToken == "" || request.Code != "" {
			writeError(w, r, http.StatusBadRequest, "invalid_grant", "refresh token grant is malformed")
			return
		}
		pair, err = handler.service.Refresh(r.Context(), request.RefreshToken, request.DeviceID)
	default:
		writeError(w, r, http.StatusBadRequest, "unsupported_grant_type", "unsupported grant_type")
		return
	}
	if err != nil {
		writeAuthError(w, r, err)
		return
	}
	writeData(w, r, http.StatusOK, tokenResponse{
		AccessToken: pair.AccessToken, RefreshToken: pair.RefreshToken,
		TokenType: "Bearer", ExpiresIn: int64(pair.AccessExpiresIn / time.Second),
		RefreshExpiresIn: int64(pair.RefreshExpiresIn / time.Second),
	})
}

func preventCredentialCaching(w http.ResponseWriter) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Pragma", "no-cache")
}

func decodeJSON(w http.ResponseWriter, r *http.Request, destination any) error {
	r.Body = http.MaxBytesReader(w, r.Body, maxJSONBodyBytes)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return errors.New("request body must contain one JSON object")
	}
	return nil
}

func writeJSONDecodeError(w http.ResponseWriter, r *http.Request, err error) {
	var maxBytesError *http.MaxBytesError
	if errors.As(err, &maxBytesError) {
		writeError(w, r, http.StatusRequestEntityTooLarge, "request_too_large", "request body is too large")
		return
	}
	writeError(w, r, http.StatusBadRequest, "invalid_request", "invalid JSON request")
}

func writeAuthError(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, auth.ErrInvalidCredentials),
		errors.Is(err, auth.ErrAuthorizationCodeInvalid),
		errors.Is(err, auth.ErrRefreshTokenInvalid):
		writeError(w, r, http.StatusUnauthorized, "invalid_credentials", "invalid credentials")
	case errors.Is(err, auth.ErrChallengeExpired):
		writeError(w, r, http.StatusUnauthorized, "challenge_expired", "login challenge expired")
	case errors.Is(err, auth.ErrChallengeLocked):
		writeError(w, r, http.StatusTooManyRequests, "challenge_locked", "login challenge locked")
	case errors.Is(err, auth.ErrAccountDisabled),
		errors.Is(err, auth.ErrDeviceRevoked),
		errors.Is(err, auth.ErrCredentialMismatch):
		writeError(w, r, http.StatusUnauthorized, "invalid_credentials", "invalid credentials")
	default:
		writeError(w, r, http.StatusInternalServerError, "internal_error", "internal server error")
	}
}
