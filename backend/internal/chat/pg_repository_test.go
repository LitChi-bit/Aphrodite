package chat

import (
	"errors"
	"testing"
	"time"
)

func TestCursorRoundTrip(t *testing.T) {
	createdAt := time.Date(2026, 7, 31, 9, 0, 0, 0, time.UTC)
	encoded := encodeCursor(createdAt, "message-example")
	decoded, err := decodeCursor(encoded)
	if err != nil {
		t.Fatalf("decode cursor: %v", err)
	}
	if decoded.CreatedAt == nil || !decoded.CreatedAt.Equal(createdAt) || decoded.ID != "message-example" {
		t.Fatalf("unexpected cursor: %#v", decoded)
	}
}

func TestDecodeCursorRejectsInvalidInput(t *testing.T) {
	if _, err := decodeCursor("not-a-valid-cursor"); !errors.Is(err, ErrInvalidPage) {
		t.Fatalf("invalid cursor error = %v, want %v", err, ErrInvalidPage)
	}
}

func TestConversationPageUsesLastReturnedItemForCursor(t *testing.T) {
	base := time.Date(2026, 7, 31, 9, 0, 0, 0, time.UTC)
	items := []Conversation{
		{ID: "conversation-3", UpdatedAt: base.Add(3 * time.Minute)},
		{ID: "conversation-2", UpdatedAt: base.Add(2 * time.Minute)},
		{ID: "conversation-1", UpdatedAt: base.Add(time.Minute)},
	}
	page, next, err := conversationPage(items, 2)
	if err != nil {
		t.Fatalf("conversation page: %v", err)
	}
	if len(page) != 2 || page[1].ID != "conversation-2" || next == "" {
		t.Fatalf("unexpected page: %#v, cursor %q", page, next)
	}
	cursor, err := decodeCursor(next)
	if err != nil || cursor.ID != "conversation-2" {
		t.Fatalf("unexpected next cursor: %#v, %v", cursor, err)
	}
}

func TestMessagePageReturnsNoCursorAtEnd(t *testing.T) {
	items := []Message{{ID: "message-1"}}
	page, next, err := messagePage(items, 2)
	if err != nil {
		t.Fatalf("message page: %v", err)
	}
	if len(page) != 1 || next != "" {
		t.Fatalf("unexpected final page: %#v, cursor %q", page, next)
	}
}

func TestMatchesCreateMessageRejectsIdempotencyPayloadMismatch(t *testing.T) {
	replyID := "reply-example"
	message := Message{
		ConversationID:  "conversation-example",
		SenderID:        "account-example",
		ClientMessageID: "client-message-example",
		Kind:            MessageKindText,
		Ciphertext:      []byte("ciphertext-example"),
		Encryption: EncryptionMetadata{
			Scheme: "mls_v1", GroupID: "group-example", Epoch: 1, Header: []byte("header-example"),
		},
		ReplyToMessageID: &replyID,
	}
	candidate := CreateMessage{
		ConversationID:   message.ConversationID,
		SenderID:         message.SenderID,
		ClientMessageID:  message.ClientMessageID,
		Kind:             message.Kind,
		Ciphertext:       []byte("different-ciphertext"),
		Encryption:       message.Encryption,
		ReplyToMessageID: message.ReplyToMessageID,
	}
	if matchesCreateMessage(message, candidate) {
		t.Fatal("different payload must not be treated as idempotent")
	}
	candidate.Ciphertext = message.Ciphertext
	if !matchesCreateMessage(message, candidate) {
		t.Fatal("identical payload must be treated as idempotent")
	}
}
