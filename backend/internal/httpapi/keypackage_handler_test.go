package httpapi

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"aphrodite/backend/internal/auth"
	"aphrodite/backend/internal/keypackage"
)

func TestKeyPackageRoutesRequireAccessToken(t *testing.T) {
	server := NewServer(discardLogger(), WithKeyPackageService(&stubKeyPackageService{}, &stubChatAuthenticator{}, stubAccessTokenVerifier{}))
	response := httptest.NewRecorder()
	server.Handler().ServeHTTP(response, httptest.NewRequest(http.MethodPut, "/v1/mls/key-packages", nil))
	assertErrorResponse(t, response, http.StatusUnauthorized, "invalid_credentials")
}

func TestPublishKeyPackagesBindsAuthenticatedDeviceAndRejectsUnknownFields(t *testing.T) {
	service := &stubKeyPackageService{}
	authenticator := &stubChatAuthenticator{claims: auth.AccessTokenClaims{AccountID: "account-example", DeviceID: "device-example", SessionID: "session-example"}}
	server := NewServer(discardLogger(), WithKeyPackageService(service, authenticator, stubAccessTokenVerifier{}))

	invalid := httptest.NewRequest(http.MethodPut, "/v1/mls/key-packages", strings.NewReader(`{"plaintext":"never"}`))
	invalid.Header.Set("Authorization", "Bearer access-example")
	invalidResponse := httptest.NewRecorder()
	server.Handler().ServeHTTP(invalidResponse, invalid)
	assertErrorResponse(t, invalidResponse, http.StatusBadRequest, "invalid_request")
	if service.publishCalls != 0 {
		t.Fatal("invalid request must not reach key package service")
	}

	body := `{"key_packages":[{"ciphersuite":"MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519","key_package":"AQI","signature":"AwQ","expires_at":"2026-07-31T01:00:00Z"}]}`
	request := httptest.NewRequest(http.MethodPut, "/v1/mls/key-packages", strings.NewReader(body))
	request.Header.Set("Authorization", "Bearer access-example")
	response := httptest.NewRecorder()
	server.Handler().ServeHTTP(response, request)
	if response.Code != http.StatusCreated {
		t.Fatalf("status = %d body = %s", response.Code, response.Body.String())
	}
	if service.publishAccountID != "account-example" || service.publishDeviceID != "device-example" || len(service.published) != 1 {
		t.Fatalf("unexpected publish input: account=%q device=%q items=%#v", service.publishAccountID, service.publishDeviceID, service.published)
	}
	if service.published[0].ID == "" || string(service.published[0].Package) != string([]byte{1, 2}) || service.published[0].CreatedAt.IsZero() || service.published[0].CreatedAt.Location() != time.UTC {
		t.Fatalf("unexpected published item: %#v", service.published[0])
	}
}

func TestListKeyPackagesHidesPublicMaterialAndClaimReturnsRawBase64(t *testing.T) {
	now := time.Date(2026, 7, 31, 0, 0, 0, 0, time.UTC)
	item := keypackage.KeyPackage{ID: "package-example", AccountID: "recipient-example", DeviceID: "device-example", Ciphersuite: "suite-example", Package: []byte{1, 2}, Signature: []byte{3, 4}, CreatedAt: now, ExpiresAt: now.Add(time.Hour)}
	service := &stubKeyPackageService{available: []keypackage.KeyPackage{item}, claimed: []keypackage.KeyPackage{item}}
	authenticator := &stubChatAuthenticator{claims: auth.AccessTokenClaims{AccountID: "requester-example", DeviceID: "device-requester", SessionID: "session-example"}}
	server := NewServer(discardLogger(), WithKeyPackageService(service, authenticator, stubAccessTokenVerifier{}))

	listRequest := httptest.NewRequest(http.MethodGet, "/v1/accounts/recipient-example/mls/key-packages?limit=2", nil)
	listRequest.Header.Set("Authorization", "Bearer access-example")
	listResponse := httptest.NewRecorder()
	server.Handler().ServeHTTP(listResponse, listRequest)
	if listResponse.Code != http.StatusOK || strings.Contains(listResponse.Body.String(), "AQI") || strings.Contains(listResponse.Body.String(), "AwQ") {
		t.Fatalf("list response must hide key material: status=%d body=%s", listResponse.Code, listResponse.Body.String())
	}
	if service.listAccountID != "recipient-example" || service.listLimit != 2 {
		t.Fatalf("unexpected list input: %q %d", service.listAccountID, service.listLimit)
	}

	claimRequest := httptest.NewRequest(http.MethodPost, "/v1/accounts/recipient-example/mls/key-packages:claim", nil)
	claimRequest.Header.Set("Authorization", "Bearer access-example")
	claimResponse := httptest.NewRecorder()
	server.Handler().ServeHTTP(claimResponse, claimRequest)
	if claimResponse.Code != http.StatusOK {
		t.Fatalf("claim status = %d body = %s", claimResponse.Code, claimResponse.Body.String())
	}
	var envelope struct {
		Data []struct {
			KeyPackage string `json:"key_package"`
			Signature  string `json:"signature"`
		} `json:"data"`
	}
	if err := json.NewDecoder(claimResponse.Body).Decode(&envelope); err != nil || len(envelope.Data) != 1 || envelope.Data[0].KeyPackage != base64.RawStdEncoding.EncodeToString(item.Package) || envelope.Data[0].Signature != base64.RawStdEncoding.EncodeToString(item.Signature) {
		t.Fatalf("unexpected claim response: %#v, %v", envelope, err)
	}
}

type stubKeyPackageService struct {
	publishCalls     int
	publishAccountID string
	publishDeviceID  string
	published        []keypackage.Publish
	available        []keypackage.KeyPackage
	claimed          []keypackage.KeyPackage
	listAccountID    string
	listLimit        int
}

func (service *stubKeyPackageService) Publish(_ context.Context, accountID, deviceID string, items []keypackage.Publish) error {
	service.publishCalls++
	service.publishAccountID, service.publishDeviceID = accountID, deviceID
	service.published = items
	return nil
}

func (service *stubKeyPackageService) ListAvailable(_ context.Context, accountID string, limit int, _ time.Time) ([]keypackage.KeyPackage, error) {
	service.listAccountID, service.listLimit = accountID, limit
	return service.available, nil
}

func (service *stubKeyPackageService) Claim(_ context.Context, _ string, _ int, _ time.Time) ([]keypackage.KeyPackage, error) {
	return service.claimed, nil
}
