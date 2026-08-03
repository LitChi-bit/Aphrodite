package httpapi

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"aphrodite/backend/internal/auth"
	"aphrodite/backend/internal/chat"
)

func TestChatAPIEndToEnd(t *testing.T) {
	fixture := newChatE2EFixture(t)
	conversationID := "10000000-0000-4000-8000-000000000001"
	clientMessageID := "20000000-0000-4000-8000-000000000001"
	firstPayload := chatE2EMessagePayload(clientMessageID, "Y2lwaGVydGV4dC1vbmU")

	response := fixture.request(t, fixture.memberToken, http.MethodGet, "/v1/conversations", nil)
	if response.Code != http.StatusOK {
		t.Fatalf("member conversation list status = %d body = %s", response.Code, response.Body.String())
	}
	var conversations struct {
		Data []struct {
			ID        string   `json:"id"`
			MemberIDs []string `json:"member_ids"`
		} `json:"data"`
	}
	decodeChatE2EResponse(t, response, &conversations)
	if len(conversations.Data) != 1 || conversations.Data[0].ID != conversationID || len(conversations.Data[0].MemberIDs) != 2 {
		t.Fatalf("unexpected conversations: %#v", conversations.Data)
	}

	response = fixture.request(t, fixture.outsiderToken, http.MethodGet, "/v1/conversations/"+conversationID+"/messages", nil)
	assertChatE2EError(t, response, http.StatusNotFound, "not_found")

	response = fixture.request(t, fixture.memberToken, http.MethodPost, "/v1/conversations/"+conversationID+"/messages", firstPayload)
	if response.Code != http.StatusCreated {
		t.Fatalf("first message status = %d body = %s", response.Code, response.Body.String())
	}
	var firstMessage struct {
		Data struct {
			ID              string `json:"id"`
			ClientMessageID string `json:"client_message_id"`
			Ciphertext      string `json:"ciphertext"`
		} `json:"data"`
	}
	decodeChatE2EResponse(t, response, &firstMessage)
	if firstMessage.Data.ID == "" || firstMessage.Data.ClientMessageID != clientMessageID || firstMessage.Data.Ciphertext != "Y2lwaGVydGV4dC1vbmU" {
		t.Fatalf("unexpected first message: %#v", firstMessage.Data)
	}

	response = fixture.request(t, fixture.memberToken, http.MethodPost, "/v1/conversations/"+conversationID+"/messages", firstPayload)
	if response.Code != http.StatusOK {
		t.Fatalf("idempotent message status = %d body = %s", response.Code, response.Body.String())
	}

	conflictingPayload := chatE2EMessagePayload(clientMessageID, "Y2lwaGVydGV4dC10d28")
	response = fixture.request(t, fixture.memberToken, http.MethodPost, "/v1/conversations/"+conversationID+"/messages", conflictingPayload)
	assertChatE2EError(t, response, http.StatusConflict, "message_conflict")

	secondPayload := chatE2EMessagePayload("20000000-0000-4000-8000-000000000002", "Y2lwaGVydGV4dC10aHJlZQ")
	response = fixture.request(t, fixture.memberToken, http.MethodPost, "/v1/conversations/"+conversationID+"/messages", secondPayload)
	if response.Code != http.StatusCreated {
		t.Fatalf("second message status = %d body = %s", response.Code, response.Body.String())
	}

	response = fixture.request(t, fixture.memberToken, http.MethodGet, "/v1/conversations/"+conversationID+"/messages?limit=1", nil)
	if response.Code != http.StatusOK {
		t.Fatalf("first message page status = %d body = %s", response.Code, response.Body.String())
	}
	var firstPage struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
		Meta Meta `json:"meta"`
	}
	decodeChatE2EResponse(t, response, &firstPage)
	if len(firstPage.Data) != 1 || firstPage.Meta.NextCursor == nil || *firstPage.Meta.NextCursor == "" {
		t.Fatalf("unexpected first message page: %#v", firstPage)
	}

	response = fixture.request(t, fixture.memberToken, http.MethodGet, "/v1/conversations/"+conversationID+"/messages?limit=1&cursor="+url.QueryEscape(*firstPage.Meta.NextCursor), nil)
	if response.Code != http.StatusOK {
		t.Fatalf("second message page status = %d body = %s", response.Code, response.Body.String())
	}
	var secondPage struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	decodeChatE2EResponse(t, response, &secondPage)
	if len(secondPage.Data) != 1 || secondPage.Data[0].ID == firstPage.Data[0].ID {
		t.Fatalf("unexpected second message page: %#v", secondPage)
	}

	var plaintextColumns int
	if err := fixture.pool.QueryRow(context.Background(), `SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'messages' AND column_name IN ('plaintext', 'decrypted_text')`).Scan(&plaintextColumns); err != nil {
		t.Fatalf("check message columns: %v", err)
	}
	if plaintextColumns != 0 {
		t.Fatalf("messages table exposes %d plaintext columns", plaintextColumns)
	}
}

type chatE2EFixture struct {
	pool          *pgxpool.Pool
	handler       http.Handler
	memberToken   string
	outsiderToken string
}

func newChatE2EFixture(t *testing.T) chatE2EFixture {
	t.Helper()
	pool := chatE2EPool(t)
	truncateChatE2ETables(t, pool)
	t.Cleanup(func() { truncateChatE2ETables(t, pool) })

	ctx := context.Background()
	now := time.Now().UTC().Truncate(time.Second)
	memberAccountID := "30000000-0000-4000-8000-000000000001"
	peerAccountID := "30000000-0000-4000-8000-000000000002"
	outsiderAccountID := "30000000-0000-4000-8000-000000000003"
	conversationID := "10000000-0000-4000-8000-000000000001"
	memberDeviceID := "40000000-0000-4000-8000-000000000001"
	outsiderDeviceID := "40000000-0000-4000-8000-000000000003"
	memberSessionID := "50000000-0000-4000-8000-000000000001"
	outsiderSessionID := "50000000-0000-4000-8000-000000000003"

	for _, account := range []struct {
		id       string
		username string
	}{
		{id: memberAccountID, username: "chat-member"},
		{id: peerAccountID, username: "chat-peer"},
		{id: outsiderAccountID, username: "chat-outsider"},
	} {
		if _, err := pool.Exec(ctx, `INSERT INTO accounts (id, username, email, display_name, password_hash, status, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, 'active', $6, $6)`, account.id, account.username, account.username+"@example.test", account.username, "e2e-test-password-hash", now); err != nil {
			t.Fatalf("insert %s account: %v", account.username, err)
		}
	}
	for _, device := range []struct {
		id        string
		accountID string
	}{
		{id: memberDeviceID, accountID: memberAccountID},
		{id: outsiderDeviceID, accountID: outsiderAccountID},
	} {
		if _, err := pool.Exec(ctx, `INSERT INTO devices (id, account_id, name, platform, identity_public_key, created_at, updated_at) VALUES ($1, $2, 'E2E test device', 'android', $3, $4, $4)`, device.id, device.accountID, []byte("e2e-test-public-key"), now); err != nil {
			t.Fatalf("insert device: %v", err)
		}
	}
	for _, session := range []struct {
		id        string
		accountID string
		deviceID  string
	}{
		{id: memberSessionID, accountID: memberAccountID, deviceID: memberDeviceID},
		{id: outsiderSessionID, accountID: outsiderAccountID, deviceID: outsiderDeviceID},
	} {
		if _, err := pool.Exec(ctx, `INSERT INTO auth_sessions (id, account_id, device_id, expires_at, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $5)`, session.id, session.accountID, session.deviceID, now.Add(time.Hour), now); err != nil {
			t.Fatalf("insert session: %v", err)
		}
	}
	if _, err := pool.Exec(ctx, `INSERT INTO conversations (id, kind, name, encryption_scheme, created_at, updated_at) VALUES ($1, 'direct', '', 'mls_v1', $2, $2)`, conversationID, now); err != nil {
		t.Fatalf("insert conversation: %v", err)
	}
	for _, accountID := range []string{memberAccountID, peerAccountID} {
		if _, err := pool.Exec(ctx, `INSERT INTO conversation_members (conversation_id, account_id, role, joined_at) VALUES ($1, $2, 'member', $3)`, conversationID, accountID, now); err != nil {
			t.Fatalf("insert conversation member: %v", err)
		}
	}

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
	repository := auth.NewPostgresRepository(pool)
	service, err := auth.NewService(auth.Dependencies{
		Accounts: repository, Devices: repository, Challenges: repository, Sessions: repository,
		Passwords: auth.BcryptPasswordVerifier{}, Hasher: auth.SHA256TokenHasher{},
		Credentials: auth.SecureCredentialGenerator{}, IDs: auth.RandomIDGenerator{}, AccessTokens: issuer,
	})
	if err != nil {
		t.Fatalf("create auth service: %v", err)
	}
	memberToken, err := issuer.IssueAccessToken(memberAccountID, memberDeviceID, memberSessionID, now.Add(time.Hour))
	if err != nil {
		t.Fatalf("issue member token: %v", err)
	}
	outsiderToken, err := issuer.IssueAccessToken(outsiderAccountID, outsiderDeviceID, outsiderSessionID, now.Add(time.Hour))
	if err != nil {
		t.Fatalf("issue outsider token: %v", err)
	}
	server := NewServer(discardLogger(), WithChatService(chat.NewPostgresRepository(pool), service, verifier))
	return chatE2EFixture{pool: pool, handler: server.Handler(), memberToken: memberToken, outsiderToken: outsiderToken}
}

func chatE2EPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	databaseURL := strings.TrimSpace(os.Getenv("APHRODITE_TEST_DATABASE_URL"))
	if databaseURL == "" {
		t.Skip("requires APHRODITE_TEST_DATABASE_URL; no database connection attempted")
	}
	configuration, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		t.Fatalf("parse APHRODITE_TEST_DATABASE_URL: %v", err)
	}
	if !strings.HasSuffix(strings.ToLower(configuration.ConnConfig.Database), "_test") {
		t.Fatalf("refusing chat E2E test against non-test database %q", configuration.ConnConfig.Database)
	}
	pool, err := pgxpool.NewWithConfig(context.Background(), configuration)
	if err != nil {
		t.Fatalf("create chat E2E pool: %v", err)
	}
	t.Cleanup(pool.Close)
	if err := pool.Ping(context.Background()); err != nil {
		t.Fatalf("ping chat E2E database: %v", err)
	}
	return pool
}

func truncateChatE2ETables(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	if _, err := pool.Exec(context.Background(), `TRUNCATE conversations, accounts CASCADE`); err != nil {
		t.Fatalf("truncate chat E2E database: %v", err)
	}
}

func (fixture chatE2EFixture) request(t *testing.T, token, method, path string, body any) *httptest.ResponseRecorder {
	t.Helper()
	var encodedBody *bytes.Reader
	if body == nil {
		encodedBody = bytes.NewReader(nil)
	} else {
		encoded, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("marshal request: %v", err)
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

func chatE2EMessagePayload(clientMessageID, ciphertext string) map[string]any {
	return map[string]any{
		"client_message_id": clientMessageID,
		"kind":              "text",
		"ciphertext":        ciphertext,
		"encryption": map[string]any{
			"scheme": "mls_v1", "group_id": "e2e-group", "epoch": 7, "header": "ZTItdGVzdC1oZWFkZXI",
		},
	}
}

func decodeChatE2EResponse(t *testing.T, response *httptest.ResponseRecorder, destination any) {
	t.Helper()
	if err := json.NewDecoder(response.Body).Decode(destination); err != nil {
		t.Fatalf("decode response body %q: %v", response.Body.String(), err)
	}
}

func assertChatE2EError(t *testing.T, response *httptest.ResponseRecorder, status int, code string) {
	t.Helper()
	if response.Code != status {
		t.Fatalf("status = %d, want %d; body = %s", response.Code, status, response.Body.String())
	}
	var envelope ErrorEnvelope
	decodeChatE2EResponse(t, response, &envelope)
	if envelope.Error.Code != code {
		t.Fatalf("error code = %q, want %q", envelope.Error.Code, code)
	}
}
