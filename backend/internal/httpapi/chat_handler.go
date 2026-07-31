package httpapi

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"aphrodite/backend/internal/auth"
	"aphrodite/backend/internal/chat"
)

const maxChatRequestBodyBytes = 1 << 20

type ChatService interface {
	ListConversations(ctx context.Context, accountID string, page chat.Page) ([]chat.Conversation, string, error)
	ListMessages(ctx context.Context, accountID, conversationID string, page chat.Page) ([]chat.Message, string, error)
	CreateMessage(ctx context.Context, accountID string, message chat.CreateMessage) (chat.Message, bool, error)
}

type chatHandler struct {
	service       ChatService
	authenticator AccessTokenAuthenticator
	verifier      auth.AccessTokenVerifier
	now           func() time.Time
	newID         func() (string, error)
}

type conversationResponse struct {
	ID               string    `json:"id"`
	Kind             string    `json:"kind"`
	Name             string    `json:"name"`
	MemberIDs        []string  `json:"member_ids"`
	EncryptionScheme string    `json:"encryption_scheme"`
	CreatedAt        time.Time `json:"created_at"`
	UpdatedAt        time.Time `json:"updated_at"`
}

type messageResponse struct {
	ID              string     `json:"id"`
	ConversationID  string     `json:"conversation_id"`
	SenderID        string     `json:"sender_id"`
	ClientMessageID string     `json:"client_message_id"`
	Kind            string     `json:"kind"`
	Ciphertext      string     `json:"ciphertext"`
	Encryption      encryption `json:"encryption"`
	ReplyTo         *string    `json:"reply_to"`
	CreatedAt       time.Time  `json:"created_at"`
	EditedAt        *time.Time `json:"edited_at"`
	DeletedAt       *time.Time `json:"deleted_at"`
}

type encryption struct {
	Scheme  string `json:"scheme"`
	GroupID string `json:"group_id"`
	Epoch   int64  `json:"epoch"`
	Header  string `json:"header"`
}

type createMessageRequest struct {
	ClientMessageID string     `json:"client_message_id"`
	Kind            string     `json:"kind"`
	Ciphertext      string     `json:"ciphertext"`
	Encryption      encryption `json:"encryption"`
	ReplyTo         *string    `json:"reply_to"`
}

func (handler chatHandler) register(mux *http.ServeMux) {
	mux.HandleFunc("GET /v1/conversations", requireAccessToken(handler.authenticator, handler.verifier, handler.listConversations))
	mux.HandleFunc("GET /v1/conversations/{conversation_id}/messages", requireAccessToken(handler.authenticator, handler.verifier, handler.listMessages))
	mux.HandleFunc("POST /v1/conversations/{conversation_id}/messages", requireAccessToken(handler.authenticator, handler.verifier, handler.createMessage))
	mux.HandleFunc("/v1/conversations", methodNotAllowed(http.MethodGet))
	mux.HandleFunc("/v1/conversations/{conversation_id}/messages", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Allow", http.MethodGet+", "+http.MethodPost)
		writeError(w, r, http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed")
	})
}

func (handler chatHandler) listConversations(w http.ResponseWriter, r *http.Request) {
	subject, ok := handler.subject(w, r)
	if !ok {
		return
	}
	page, ok := handler.page(w, r)
	if !ok {
		return
	}
	items, next, err := handler.service.ListConversations(r.Context(), subject.AccountID, page)
	if err != nil {
		handler.writeError(w, r, err)
		return
	}
	response := make([]conversationResponse, 0, len(items))
	for _, item := range items {
		response = append(response, conversationResponse{
			ID: item.ID, Kind: string(item.Kind), Name: item.Name,
			MemberIDs: item.ParticipantIDs, EncryptionScheme: item.EncryptionScheme,
			CreatedAt: item.CreatedAt, UpdatedAt: item.UpdatedAt,
		})
	}
	writePagedData(w, r, http.StatusOK, response, next)
}

func (handler chatHandler) listMessages(w http.ResponseWriter, r *http.Request) {
	subject, ok := handler.subject(w, r)
	if !ok {
		return
	}
	conversationID := r.PathValue("conversation_id")
	if strings.TrimSpace(conversationID) == "" {
		writeError(w, r, http.StatusBadRequest, "invalid_request", "conversation_id is required")
		return
	}
	page, ok := handler.page(w, r)
	if !ok {
		return
	}
	items, next, err := handler.service.ListMessages(r.Context(), subject.AccountID, conversationID, page)
	if err != nil {
		handler.writeError(w, r, err)
		return
	}
	response := make([]messageResponse, 0, len(items))
	for _, item := range items {
		response = append(response, toMessageResponse(item))
	}
	writePagedData(w, r, http.StatusOK, response, next)
}

func (handler chatHandler) createMessage(w http.ResponseWriter, r *http.Request) {
	subject, ok := handler.subject(w, r)
	if !ok {
		return
	}
	conversationID := r.PathValue("conversation_id")
	if strings.TrimSpace(conversationID) == "" {
		writeError(w, r, http.StatusBadRequest, "invalid_request", "conversation_id is required")
		return
	}
	request, ok := decodeCreateMessageRequest(w, r)
	if !ok {
		return
	}
	messageID, err := handler.newID()
	if err != nil {
		writeError(w, r, http.StatusInternalServerError, "internal_error", "internal server error")
		return
	}
	ciphertext, err := base64.RawStdEncoding.DecodeString(request.Ciphertext)
	if err != nil {
		writeError(w, r, http.StatusBadRequest, "invalid_request", "ciphertext must be base64")
		return
	}
	header, err := base64.RawStdEncoding.DecodeString(request.Encryption.Header)
	if err != nil {
		writeError(w, r, http.StatusBadRequest, "invalid_request", "encryption header must be base64")
		return
	}
	message := chat.CreateMessage{
		ID: messageID, ConversationID: conversationID, SenderID: subject.AccountID,
		ClientMessageID: request.ClientMessageID, Kind: chat.MessageKind(request.Kind),
		Ciphertext: ciphertext, ReplyToMessageID: request.ReplyTo, CreatedAt: handler.now().UTC(),
		Encryption: chat.EncryptionMetadata{Scheme: request.Encryption.Scheme, GroupID: request.Encryption.GroupID, Epoch: request.Encryption.Epoch, Header: header},
	}
	created, idempotent, err := handler.service.CreateMessage(r.Context(), subject.AccountID, message)
	if err != nil {
		handler.writeError(w, r, err)
		return
	}
	status := http.StatusCreated
	if idempotent {
		status = http.StatusOK
	}
	writeData(w, r, status, toMessageResponse(created))
}

func (handler chatHandler) subject(w http.ResponseWriter, r *http.Request) (authenticatedSubject, bool) {
	subject, err := authenticatedSubjectFromContext(r.Context())
	if err != nil {
		writeError(w, r, http.StatusUnauthorized, "invalid_credentials", "invalid credentials")
		return authenticatedSubject{}, false
	}
	return subject, true
}

func (handler chatHandler) page(w http.ResponseWriter, r *http.Request) (chat.Page, bool) {
	limit := 50
	if rawLimit := r.URL.Query().Get("limit"); rawLimit != "" {
		parsed, err := strconv.Atoi(rawLimit)
		if err != nil || parsed < 1 || parsed > 100 {
			writeError(w, r, http.StatusBadRequest, "invalid_request", "limit must be between 1 and 100")
			return chat.Page{}, false
		}
		limit = parsed
	}
	return chat.Page{Cursor: r.URL.Query().Get("cursor"), Limit: limit}, true
}

func (handler chatHandler) writeError(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, chat.ErrInvalidPage), errors.Is(err, chat.ErrInvalidMessage), errors.Is(err, chat.ErrInvalidConversation):
		writeError(w, r, http.StatusBadRequest, "invalid_request", "invalid request")
	case errors.Is(err, chat.ErrConversationNotFound), errors.Is(err, chat.ErrMembershipNotFound), errors.Is(err, chat.ErrMessageNotFound):
		writeError(w, r, http.StatusNotFound, "not_found", "resource not found")
	case errors.Is(err, chat.ErrMessageConflict):
		writeError(w, r, http.StatusConflict, "message_conflict", "client message conflicts with existing message")
	default:
		writeError(w, r, http.StatusInternalServerError, "internal_error", "internal server error")
	}
}

func decodeCreateMessageRequest(w http.ResponseWriter, r *http.Request) (createMessageRequest, bool) {
	r.Body = http.MaxBytesReader(w, r.Body, maxChatRequestBodyBytes)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	var request createMessageRequest
	if err := decoder.Decode(&request); err != nil || decoder.Decode(&struct{}{}) != io.EOF {
		writeError(w, r, http.StatusBadRequest, "invalid_request", "invalid request body")
		return createMessageRequest{}, false
	}
	return request, true
}

func toMessageResponse(message chat.Message) messageResponse {
	return messageResponse{
		ID: message.ID, ConversationID: message.ConversationID, SenderID: message.SenderID,
		ClientMessageID: message.ClientMessageID, Kind: string(message.Kind),
		Ciphertext: base64.RawStdEncoding.EncodeToString(message.Ciphertext), ReplyTo: message.ReplyToMessageID,
		CreatedAt: message.CreatedAt, EditedAt: message.EditedAt, DeletedAt: message.DeletedAt,
		Encryption: encryption{Scheme: message.Encryption.Scheme, GroupID: message.Encryption.GroupID, Epoch: message.Encryption.Epoch, Header: base64.RawStdEncoding.EncodeToString(message.Encryption.Header)},
	}
}
