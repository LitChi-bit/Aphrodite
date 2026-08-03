package httpapi

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"aphrodite/backend/internal/auth"
	"aphrodite/backend/internal/keypackage"
)

func TestKeyPackageAPIEndToEnd(t *testing.T) {
	fixture := newKeyPackageE2EFixture(t)
	expiresAt := time.Now().UTC().Add(time.Hour).Format(time.RFC3339)
	publish := map[string]any{
		"key_packages": []map[string]any{
			{"ciphersuite": "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519", "key_package": "AQI", "signature": "AwQ", "expires_at": expiresAt},
			{"ciphersuite": "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519", "key_package": "BQY", "signature": "Bwg", "expires_at": expiresAt},
		},
	}
	response := fixture.request(t, fixture.ownerToken, http.MethodPut, "/v1/mls/key-packages", publish)
	if response.Code != http.StatusCreated {
		t.Fatalf("publish status = %d body = %s", response.Code, response.Body.String())
	}

	response = fixture.request(t, fixture.requesterToken, http.MethodGet, "/v1/accounts/"+fixture.ownerAccountID+"/mls/key-packages?limit=2", nil)
	if response.Code != http.StatusOK {
		t.Fatalf("list status = %d body = %s", response.Code, response.Body.String())
	}
	if containsKeyMaterial(response.Body.String()) {
		t.Fatalf("availability response leaked key material: %s", response.Body.String())
	}
	var available struct {
		Data []keyPackageAvailabilityResponse `json:"data"`
	}
	decodeChatE2EResponse(t, response, &available)
	if len(available.Data) != 2 {
		t.Fatalf("available count = %d, want 2", len(available.Data))
	}

	responses := make(chan *httpResponse, 2)
	var group sync.WaitGroup
	for range 2 {
		group.Add(1)
		go func() {
			deferred := fixture.requestWithoutTest(fixture.requesterToken, http.MethodPost, "/v1/accounts/"+fixture.ownerAccountID+"/mls/key-packages:claim?limit=1", nil)
			responses <- &httpResponse{status: deferred.Code, body: deferred.Body.String()}
			group.Done()
		}()
	}
	group.Wait()
	close(responses)

	claimed := make(map[string]struct{})
	for response := range responses {
		if response.status != http.StatusOK {
			t.Fatalf("claim status = %d body = %s", response.status, response.body)
		}
		var envelope struct {
			Data []claimedKeyPackageResponse `json:"data"`
		}
		if err := json.Unmarshal([]byte(response.body), &envelope); err != nil {
			t.Fatalf("decode claim response: %v", err)
		}
		if len(envelope.Data) != 1 {
			t.Fatalf("claim count = %d, want 1: %s", len(envelope.Data), response.body)
		}
		item := envelope.Data[0]
		if item.KeyPackage == "" || item.Signature == "" {
			t.Fatalf("claim missing key material: %#v", item)
		}
		if _, exists := claimed[item.ID]; exists {
			t.Fatalf("duplicate key package claimed: %s", item.ID)
		}
		claimed[item.ID] = struct{}{}
	}
	if len(claimed) != 2 {
		t.Fatalf("distinct claimed count = %d, want 2", len(claimed))
	}

	response = fixture.request(t, fixture.requesterToken, http.MethodPost, "/v1/accounts/"+fixture.ownerAccountID+"/mls/key-packages:claim", nil)
	if response.Code != http.StatusOK {
		t.Fatalf("empty claim status = %d body = %s", response.Code, response.Body.String())
	}
	var empty struct {
		Data []claimedKeyPackageResponse `json:"data"`
	}
	decodeChatE2EResponse(t, response, &empty)
	if len(empty.Data) != 0 {
		t.Fatalf("remaining claimed count = %d, want 0", len(empty.Data))
	}

	var privateColumns int
	if err := fixture.pool.QueryRow(context.Background(), `SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'mls_key_packages' AND column_name IN ('private_key', 'secret', 'plaintext', 'decrypted_text')`).Scan(&privateColumns); err != nil {
		t.Fatalf("check key package columns: %v", err)
	}
	if privateColumns != 0 {
		t.Fatalf("key package table exposes %d prohibited columns", privateColumns)
	}
}

type httpResponse struct {
	status int
	body   string
}

func (fixture keyPackageE2EFixture) requestWithoutTest(token, method, path string, body any) *httptest.ResponseRecorder {
	var encodedBody *bytes.Reader
	if body == nil {
		encodedBody = bytes.NewReader(nil)
	} else {
		encoded, err := json.Marshal(body)
		if err != nil {
			return httptest.NewRecorder()
		}
		encodedBody = bytes.NewReader(encoded)
	}
	request := httptest.NewRequest(method, path, encodedBody)
	request.Header.Set("Authorization", "Bearer "+token)
	if body != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	response := httptest.NewRecorder()
	fixture.handler.ServeHTTP(response, request)
	return response
}

type keyPackageE2EFixture struct {
	chatE2EFixture
	ownerAccountID string
	ownerToken     string
	requesterToken string
}

func newKeyPackageE2EFixture(t *testing.T) keyPackageE2EFixture {
	t.Helper()
	base := newChatE2EFixture(t)
	const ownerAccountID = "30000000-0000-4000-8000-000000000001"
	const ownerDeviceID = "40000000-0000-4000-8000-000000000001"
	const requesterAccountID = "30000000-0000-4000-8000-000000000003"
	const requesterDeviceID = "40000000-0000-4000-8000-000000000003"
	const ownerSessionID = "50000000-0000-4000-8000-000000000001"
	const requesterSessionID = "50000000-0000-4000-8000-000000000003"

	issuer, verifier := keyPackageE2ETokenPair(t)
	ownerToken, err := issuer.IssueAccessToken(ownerAccountID, ownerDeviceID, ownerSessionID, time.Now().UTC().Add(time.Hour))
	if err != nil {
		t.Fatalf("issue owner token: %v", err)
	}
	requesterToken, err := issuer.IssueAccessToken(requesterAccountID, requesterDeviceID, requesterSessionID, time.Now().UTC().Add(time.Hour))
	if err != nil {
		t.Fatalf("issue requester token: %v", err)
	}

	repository := auth.NewPostgresRepository(base.pool)
	service, err := auth.NewService(auth.Dependencies{
		Accounts: repository, Devices: repository, Challenges: repository, Sessions: repository,
		Passwords: auth.BcryptPasswordVerifier{}, Hasher: auth.SHA256TokenHasher{},
		Credentials: auth.SecureCredentialGenerator{}, IDs: auth.RandomIDGenerator{}, AccessTokens: issuer,
	})
	if err != nil {
		t.Fatalf("create authentication service: %v", err)
	}
	server := NewServer(discardLogger(), WithKeyPackageService(keypackage.NewPostgresRepository(base.pool), service, verifier))
	return keyPackageE2EFixture{
		chatE2EFixture: chatE2EFixture{pool: base.pool, handler: server.Handler()},
		ownerAccountID: ownerAccountID, ownerToken: ownerToken, requesterToken: requesterToken,
	}
}

func keyPackageE2ETokenPair(t *testing.T) (auth.AccessTokenIssuer, auth.AccessTokenVerifier) {
	t.Helper()
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate access token key: %v", err)
	}
	issuer, err := auth.NewEd25519AccessTokenIssuer(privateKey, time.Now)
	if err != nil {
		t.Fatalf("create access token issuer: %v", err)
	}
	verifier, err := auth.NewEd25519AccessTokenVerifier(publicKey, time.Now)
	if err != nil {
		t.Fatalf("create access token verifier: %v", err)
	}
	return issuer, verifier
}

func containsKeyMaterial(body string) bool {
	for _, value := range [][]byte{{1, 2}, {3, 4}, {5, 6}, {7, 8}} {
		if strings.Contains(body, base64.RawStdEncoding.EncodeToString(value)) {
			return true
		}
	}
	return false
}
