package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"aphrodite/backend/internal/auth"
	"aphrodite/backend/internal/chat"
)

func TestChatRoutesRequireAccessToken(t *testing.T) {
	server := NewServer(discardLogger(), WithChatService(&stubChatService{}, &stubChatAuthenticator{}, stubAccessTokenVerifier{}))
	response := httptest.NewRecorder()
	server.Handler().ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/v1/conversations", nil))
	assertErrorResponse(t, response, http.StatusUnauthorized, "invalid_credentials")
}

func TestListConversationsUsesAuthenticatedAccountAndCursor(t *testing.T) {
	now := time.Date(2026, 7, 31, 10, 0, 0, 0, time.UTC)
	service := &stubChatService{conversations: []chat.Conversation{{
		ID: "conversation-example", Kind: chat.ConversationKindGroup, Name: "Example group",
		EncryptionScheme: "mls_v1", CreatedAt: now, UpdatedAt: now,
	}}, nextCursor: "cursor-example"}
	authenticator := &stubChatAuthenticator{claims: auth.AccessTokenClaims{AccountID: "account-example", DeviceID: "device-example", SessionID: "session-example"}}
	server := NewServer(discardLogger(), WithChatService(service, authenticator, stubAccessTokenVerifier{}))
	request := httptest.NewRequest(http.MethodGet, "/v1/conversations?cursor=before-example&limit=20", nil)
	request.Header.Set("Authorization", "Bearer access-example")
	response := httptest.NewRecorder()
	server.Handler().ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d body = %s", response.Code, response.Body.String())
	}
	if service.listAccountID != "account-example" || service.conversationPage.Limit != 20 || service.conversationPage.Cursor != "before-example" {
		t.Fatalf("unexpected repository input: account=%q page=%#v", service.listAccountID, service.conversationPage)
	}
	var envelope struct {
		Meta Meta `json:"meta"`
	}
	if err := json.NewDecoder(response.Body).Decode(&envelope); err != nil || envelope.Meta.NextCursor == nil || *envelope.Meta.NextCursor != "cursor-example" {
		t.Fatalf("unexpected cursor envelope: %#v, %v", envelope, err)
	}
}

func TestCreateMessageRejectsUnknownRequestFields(t *testing.T) {
	service := &stubChatService{}
	authenticator := &stubChatAuthenticator{claims: auth.AccessTokenClaims{AccountID: "account-example", DeviceID: "device-example", SessionID: "session-example"}}
	server := NewServer(discardLogger(), WithChatService(service, authenticator, stubAccessTokenVerifier{}))
	request := httptest.NewRequest(http.MethodPost, "/v1/conversations/conversation-example/messages", strings.NewReader(`{"plaintext":"must-not-be-accepted"}`))
	request.Header.Set("Authorization", "Bearer access-example")
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	server.Handler().ServeHTTP(response, request)

	assertErrorResponse(t, response, http.StatusBadRequest, "invalid_request")
	if service.createCalls != 0 {
		t.Fatal("invalid request must not reach chat repository")
	}
}

type stubChatAuthenticator struct{ claims auth.AccessTokenClaims }

func (authenticator *stubChatAuthenticator) AuthenticateAccessToken(_ context.Context, _ auth.AccessTokenVerifier, _ string) (auth.AccessTokenClaims, error) {
	return authenticator.claims, nil
}

type stubChatService struct {
	conversations    []chat.Conversation
	nextCursor       string
	listAccountID    string
	conversationPage chat.Page
	createCalls      int
}

func (service *stubChatService) ListConversations(_ context.Context, accountID string, page chat.Page) ([]chat.Conversation, string, error) {
	service.listAccountID, service.conversationPage = accountID, page
	return service.conversations, service.nextCursor, nil
}

func (service *stubChatService) ListMessages(context.Context, string, string, chat.Page) ([]chat.Message, string, error) {
	return nil, "", nil
}

func (service *stubChatService) CreateMessage(context.Context, string, chat.CreateMessage) (chat.Message, bool, error) {
	service.createCalls++
	return chat.Message{}, false, nil
}
