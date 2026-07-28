package httpapi

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"aphrodite/backend/internal/auth"
)

func TestCreateChallengeMapsRequestAndEnvelope(t *testing.T) {
	service := &stubAuthService{
		challengeResult: auth.ChallengeResult{
			ChallengeID: "challenge-example",
			ExpiresAt:   time.Date(2026, 7, 28, 2, 0, 0, 0, time.UTC),
		},
	}
	server := NewServer(discardLogger(), WithAuthService(service))
	body := `{"login":"example-user","device_name":"Example device","device_id":"device-example","platform":"android","identity_public_key":"` + base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{1}, 32)) + `"}`
	response := performJSONRequest(server.Handler(), http.MethodPost, "/v1/auth/challenges", body)

	if response.Code != http.StatusCreated {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	if response.Header().Get("Cache-Control") != "no-store" || response.Header().Get("Pragma") != "no-cache" {
		t.Fatalf("missing credential cache protection headers: %#v", response.Header())
	}
	if service.challengeInput.Login != "example-user" || !bytes.Equal(service.challengeInput.IdentityPublicKey, bytes.Repeat([]byte{1}, 32)) {
		t.Fatalf("unexpected service input: %#v", service.challengeInput)
	}
	var envelope struct {
		RequestID string `json:"request_id"`
		Data      struct {
			ChallengeID string `json:"challenge_id"`
			Factors     []struct {
				Type     string `json:"type"`
				Required bool   `json:"required"`
			} `json:"factors"`
		} `json:"data"`
	}
	decodeRecorder(t, response, &envelope)
	if envelope.RequestID == "" || envelope.Data.ChallengeID != "challenge-example" || len(envelope.Data.Factors) != 1 {
		t.Fatalf("unexpected response: %#v", envelope)
	}
}

func TestCreateChallengeRejectsUnknownField(t *testing.T) {
	server := NewServer(discardLogger(), WithAuthService(&stubAuthService{}))
	response := performJSONRequest(server.Handler(), http.MethodPost, "/v1/auth/challenges", `{"login":"example-user","unknown":true}`)

	assertErrorResponse(t, response, http.StatusBadRequest, "invalid_request")
}

func TestVerifyChallengeReturnsAuthorizationCode(t *testing.T) {
	service := &stubAuthService{verifyResult: auth.AuthorizationResult{
		AuthorizationCode: "authorization-example",
		ExpiresAt:         time.Date(2026, 7, 28, 2, 1, 0, 0, time.UTC),
	}}
	server := NewServer(discardLogger(), WithAuthService(service))
	response := performJSONRequest(
		server.Handler(), http.MethodPost,
		"/v1/auth/challenges/challenge-example/verify",
		`{"factor":"password","value":"example-password","step":"primary"}`,
	)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
	var envelope struct {
		Data verifyChallengeResponse `json:"data"`
	}
	decodeRecorder(t, response, &envelope)
	if !envelope.Data.Verified || envelope.Data.AuthorizationCode != "authorization-example" {
		t.Fatalf("unexpected response: %#v", envelope.Data)
	}
}

func TestAuthEndpointRejectsWrongMethod(t *testing.T) {
	server := NewServer(discardLogger(), WithAuthService(&stubAuthService{}))
	request := httptest.NewRequest(http.MethodGet, "/v1/auth/token", nil)
	response := httptest.NewRecorder()
	server.Handler().ServeHTTP(response, request)

	assertErrorResponse(t, response, http.StatusMethodNotAllowed, "method_not_allowed")
	if response.Header().Get("Allow") != http.MethodPost {
		t.Fatalf("Allow = %q", response.Header().Get("Allow"))
	}
}

func TestAuthEndpointRejectsOversizedBody(t *testing.T) {
	server := NewServer(discardLogger(), WithAuthService(&stubAuthService{}))
	oversized := `{"grant_type":"authorization_code","code":"` + string(bytes.Repeat([]byte{'a'}, maxJSONBodyBytes)) + `","device_id":"device-example"}`
	response := performJSONRequest(server.Handler(), http.MethodPost, "/v1/auth/token", oversized)

	assertErrorResponse(t, response, http.StatusRequestEntityTooLarge, "request_too_large")
}

func TestVerifyChallengeMapsLockedError(t *testing.T) {
	service := &stubAuthService{verifyError: auth.ErrChallengeLocked}
	server := NewServer(discardLogger(), WithAuthService(service))
	response := performJSONRequest(
		server.Handler(), http.MethodPost,
		"/v1/auth/challenges/challenge-example/verify",
		`{"factor":"password","value":"example-password","step":"primary"}`,
	)

	assertErrorResponse(t, response, http.StatusTooManyRequests, "challenge_locked")
	if service.verifyInput.ChallengeID != "challenge-example" {
		t.Fatalf("challenge id = %q", service.verifyInput.ChallengeID)
	}
}

func TestAuthorizationAndRefreshTokenGrants(t *testing.T) {
	service := &stubAuthService{tokenPair: auth.TokenPair{
		AccessToken: "access-example", RefreshToken: "refresh-example-new",
		AccessExpiresIn: 15 * time.Minute, RefreshExpiresIn: 30 * 24 * time.Hour,
	}}
	server := NewServer(discardLogger(), WithAuthService(service))

	authorizationResponse := performJSONRequest(server.Handler(), http.MethodPost, "/v1/auth/token", `{"grant_type":"authorization_code","code":"authorization-example","device_id":"device-example"}`)
	if authorizationResponse.Code != http.StatusOK {
		t.Fatalf("authorization status = %d", authorizationResponse.Code)
	}
	if service.exchangedCode != "authorization-example" {
		t.Fatalf("exchanged code = %q", service.exchangedCode)
	}

	refreshResponse := performJSONRequest(server.Handler(), http.MethodPost, "/v1/auth/token", `{"grant_type":"refresh_token","refresh_token":"refresh-example","device_id":"device-example"}`)
	if refreshResponse.Code != http.StatusOK {
		t.Fatalf("refresh status = %d", refreshResponse.Code)
	}
	if service.refreshedToken != "refresh-example" {
		t.Fatalf("refreshed token = %q", service.refreshedToken)
	}
	var envelope struct {
		Data tokenResponse `json:"data"`
	}
	decodeRecorder(t, refreshResponse, &envelope)
	if envelope.Data.TokenType != "Bearer" || envelope.Data.ExpiresIn != 900 || envelope.Data.RefreshExpiresIn != 2592000 {
		t.Fatalf("unexpected token response: %#v", envelope.Data)
	}
}

func TestTokenGrantHidesCredentialFailureDetails(t *testing.T) {
	service := &stubAuthService{exchangeError: auth.ErrAuthorizationCodeInvalid}
	server := NewServer(discardLogger(), WithAuthService(service))
	response := performJSONRequest(server.Handler(), http.MethodPost, "/v1/auth/token", `{"grant_type":"authorization_code","code":"invalid-example","device_id":"device-example"}`)

	assertErrorResponse(t, response, http.StatusUnauthorized, "invalid_credentials")
}

type stubAuthService struct {
	challengeInput  auth.CreateChallengeInput
	challengeResult auth.ChallengeResult
	challengeError  error
	verifyInput     auth.VerifyPasswordInput
	verifyResult    auth.AuthorizationResult
	verifyError     error
	exchangedCode   string
	refreshedToken  string
	tokenPair       auth.TokenPair
	exchangeError   error
	refreshError    error
}

func (service *stubAuthService) CreateChallenge(_ context.Context, input auth.CreateChallengeInput) (auth.ChallengeResult, error) {
	service.challengeInput = input
	return service.challengeResult, service.challengeError
}

func (service *stubAuthService) VerifyPassword(_ context.Context, input auth.VerifyPasswordInput) (auth.AuthorizationResult, error) {
	service.verifyInput = input
	return service.verifyResult, service.verifyError
}

func (service *stubAuthService) ExchangeAuthorizationCode(_ context.Context, code, deviceID string) (auth.TokenPair, error) {
	service.exchangedCode = code
	if deviceID == "" {
		return auth.TokenPair{}, errors.New("device id is required")
	}
	return service.tokenPair, service.exchangeError
}

func (service *stubAuthService) Refresh(_ context.Context, refreshToken, deviceID string) (auth.TokenPair, error) {
	service.refreshedToken = refreshToken
	if deviceID == "" {
		return auth.TokenPair{}, errors.New("device id is required")
	}
	return service.tokenPair, service.refreshError
}

func performJSONRequest(handler http.Handler, method, path, body string) *httptest.ResponseRecorder {
	request := httptest.NewRequest(method, path, bytes.NewBufferString(body))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	return response
}

func decodeRecorder(t *testing.T, response *httptest.ResponseRecorder, destination any) {
	t.Helper()
	if err := json.NewDecoder(response.Body).Decode(destination); err != nil {
		t.Fatalf("decode response: %v", err)
	}
}

func assertErrorResponse(t *testing.T, response *httptest.ResponseRecorder, status int, code string) {
	t.Helper()
	if response.Code != status {
		t.Fatalf("status = %d, want %d, body = %s", response.Code, status, response.Body.String())
	}
	var envelope ErrorEnvelope
	decodeRecorder(t, response, &envelope)
	if envelope.RequestID == "" || envelope.Error.Code != code {
		t.Fatalf("unexpected error envelope: %#v", envelope)
	}
}
