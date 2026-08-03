package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"aphrodite/backend/internal/auth"
	"aphrodite/backend/internal/mlsstate"
)

func TestMLSStateRoutesRequireAccessToken(t *testing.T) {
	server := NewServer(discardLogger(), WithMLSStateService(&stubMLSStateService{}, &stubChatAuthenticator{}, stubAccessTokenVerifier{}))
	response := httptest.NewRecorder()
	server.Handler().ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/v1/conversations/conversation-example/mls/state", nil))
	assertErrorResponse(t, response, http.StatusUnauthorized, "invalid_credentials")
}

func TestMLSCommitRejectsUnknownFields(t *testing.T) {
	service := &stubMLSStateService{}
	authenticator := &stubChatAuthenticator{claims: auth.AccessTokenClaims{AccountID: "account-example", DeviceID: "device-example", SessionID: "session-example"}}
	server := NewServer(discardLogger(), WithMLSStateService(service, authenticator, stubAccessTokenVerifier{}))
	request := httptest.NewRequest(http.MethodPut, "/v1/conversations/conversation-example/mls/state", strings.NewReader(`{"plaintext":"must-not-be-accepted"}`))
	request.Header.Set("Authorization", "Bearer access-example")
	response := httptest.NewRecorder()
	server.Handler().ServeHTTP(response, request)
	assertErrorResponse(t, response, http.StatusBadRequest, "invalid_request")
	if service.commitCalls != 0 {
		t.Fatal("invalid MLS state request must not reach service")
	}
}

func TestClaimWelcomeUsesAuthenticatedDevice(t *testing.T) {
	service := &stubMLSStateService{deliveries: []mlsstate.Delivery{{ID: "welcome-example", ConversationID: "conversation-example", Epoch: 1, WelcomeData: []byte{1}, CreatedAt: time.Date(2026, 8, 3, 0, 0, 0, 0, time.UTC)}}}
	authenticator := &stubChatAuthenticator{claims: auth.AccessTokenClaims{AccountID: "account-example", DeviceID: "device-example", SessionID: "session-example"}}
	server := NewServer(discardLogger(), WithMLSStateService(service, authenticator, stubAccessTokenVerifier{}))
	request := httptest.NewRequest(http.MethodPost, "/v1/mls/welcomes:claim", nil)
	request.Header.Set("Authorization", "Bearer access-example")
	response := httptest.NewRecorder()
	server.Handler().ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d body = %s", response.Code, response.Body.String())
	}
	if service.claimAccountID != "account-example" || service.claimDeviceID != "device-example" {
		t.Fatalf("unexpected claim subject: %q %q", service.claimAccountID, service.claimDeviceID)
	}
}

type stubMLSStateService struct {
	commitCalls    int
	claimAccountID string
	claimDeviceID  string
	deliveries     []mlsstate.Delivery
}

func (service *stubMLSStateService) Commit(context.Context, string, string, mlsstate.Commit) (mlsstate.GroupState, error) {
	service.commitCalls++
	return mlsstate.GroupState{}, nil
}
func (service *stubMLSStateService) GetState(context.Context, string, string, string) (mlsstate.GroupState, error) {
	return mlsstate.GroupState{}, mlsstate.ErrNotFound
}
func (service *stubMLSStateService) ClaimWelcome(_ context.Context, accountID, deviceID string) ([]mlsstate.Delivery, error) {
	service.claimAccountID, service.claimDeviceID = accountID, deviceID
	return service.deliveries, nil
}
func (service *stubMLSStateService) ListDeviceRoster(context.Context, string, string) ([]mlsstate.DeviceRosterEntry, error) {
	return nil, mlsstate.ErrNotFound
}
