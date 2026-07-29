package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"aphrodite/backend/internal/auth"
)

func TestDeviceRoutesRequireAccessToken(t *testing.T) {
	service := &stubDeviceService{}
	server := NewServer(discardLogger(), WithDeviceService(service, stubAccessTokenVerifier{}))
	for _, request := range []*http.Request{
		httptest.NewRequest(http.MethodGet, "/v1/devices", nil),
		httptest.NewRequest(http.MethodDelete, "/v1/devices/device-example", nil),
	} {
		response := httptest.NewRecorder()
		server.Handler().ServeHTTP(response, request)
		assertErrorResponse(t, response, http.StatusUnauthorized, "invalid_credentials")
	}
}

func TestListDevicesUsesAuthenticatedAccountAndMarksCurrent(t *testing.T) {
	now := time.Date(2026, 7, 29, 6, 0, 0, 0, time.UTC)
	service := &stubDeviceService{
		claims: auth.AccessTokenClaims{AccountID: "account-example", DeviceID: "device-current", SessionID: "session-example"},
		devices: []auth.Device{
			{ID: "device-current", AccountID: "account-example", Name: "Current phone", Platform: "android", CreatedAt: now},
			{ID: "device-other", AccountID: "account-example", Name: "Other phone", Platform: "ios", CreatedAt: now},
		},
	}
	server := NewServer(discardLogger(), WithDeviceService(service, stubAccessTokenVerifier{}))
	request := httptest.NewRequest(http.MethodGet, "/v1/devices", nil)
	request.Header.Set("Authorization", "Bearer access-example")
	response := httptest.NewRecorder()
	server.Handler().ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d body = %s", response.Code, response.Body.String())
	}
	if service.listAccountID != "account-example" {
		t.Fatalf("list account = %q", service.listAccountID)
	}
	var envelope struct {
		Data []deviceResponse `json:"data"`
	}
	if err := json.NewDecoder(response.Body).Decode(&envelope); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if len(envelope.Data) != 2 || !envelope.Data[0].Current || envelope.Data[1].Current {
		t.Fatalf("unexpected devices: %#v", envelope.Data)
	}
}

func TestRevokeDeviceUsesAuthenticatedAccount(t *testing.T) {
	service := &stubDeviceService{
		claims: auth.AccessTokenClaims{AccountID: "account-example", DeviceID: "device-current", SessionID: "session-example"},
	}
	server := NewServer(discardLogger(), WithDeviceService(service, stubAccessTokenVerifier{}))
	request := httptest.NewRequest(http.MethodDelete, "/v1/devices/device-other", nil)
	request.Header.Set("Authorization", "Bearer access-example")
	response := httptest.NewRecorder()
	server.Handler().ServeHTTP(response, request)

	if response.Code != http.StatusNoContent {
		t.Fatalf("status = %d body = %s", response.Code, response.Body.String())
	}
	if service.revokeAccountID != "account-example" || service.revokeDeviceID != "device-other" {
		t.Fatalf("unexpected revoke input: account=%q device=%q", service.revokeAccountID, service.revokeDeviceID)
	}
}

func TestRevokeDeviceHidesOtherAccountDevice(t *testing.T) {
	service := &stubDeviceService{
		claims:      auth.AccessTokenClaims{AccountID: "account-example", DeviceID: "device-current", SessionID: "session-example"},
		revokeError: auth.ErrDeviceNotFound,
	}
	server := NewServer(discardLogger(), WithDeviceService(service, stubAccessTokenVerifier{}))
	request := httptest.NewRequest(http.MethodDelete, "/v1/devices/device-other-account", nil)
	request.Header.Set("Authorization", "Bearer access-example")
	response := httptest.NewRecorder()
	server.Handler().ServeHTTP(response, request)

	assertErrorResponse(t, response, http.StatusNotFound, "device_not_found")
}

type stubDeviceService struct {
	claims          auth.AccessTokenClaims
	authError       error
	devices         []auth.Device
	listError       error
	revokeError     error
	listAccountID   string
	revokeAccountID string
	revokeDeviceID  string
}

func (service *stubDeviceService) AuthenticateAccessToken(_ context.Context, _ auth.AccessTokenVerifier, _ string) (auth.AccessTokenClaims, error) {
	if service.authError != nil {
		return auth.AccessTokenClaims{}, service.authError
	}
	if service.claims.AccountID == "" {
		return auth.AccessTokenClaims{}, errors.New("missing test claims")
	}
	return service.claims, nil
}

func (service *stubDeviceService) ListDevices(_ context.Context, accountID string) ([]auth.Device, error) {
	service.listAccountID = accountID
	return service.devices, service.listError
}

func (service *stubDeviceService) RevokeDevice(_ context.Context, accountID, deviceID string) error {
	service.revokeAccountID = accountID
	service.revokeDeviceID = deviceID
	return service.revokeError
}
