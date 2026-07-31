package chat

import (
	"errors"
	"testing"
	"time"
)

func TestPageValidate(t *testing.T) {
	for _, limit := range []int{0, 101} {
		if !errors.Is((Page{Limit: limit}).Validate(), ErrInvalidPage) {
			t.Fatalf("limit %d must be rejected", limit)
		}
	}
	if err := (Page{Limit: 50}).Validate(); err != nil {
		t.Fatalf("valid page rejected: %v", err)
	}
}

func TestCreateMessageValidate(t *testing.T) {
	message := CreateMessage{
		ID:              "message-example",
		ConversationID:  "conversation-example",
		SenderID:        "account-example",
		ClientMessageID: "client-message-example",
		Kind:            MessageKindText,
		Ciphertext:      []byte("ciphertext-example"),
		Encryption: EncryptionMetadata{
			Scheme:  "mls_v1",
			GroupID: "group-example",
			Epoch:   0,
			Header:  []byte("header-example"),
		},
		CreatedAt: time.Date(2026, 7, 31, 8, 0, 0, 0, time.UTC),
	}
	if err := message.Validate(); err != nil {
		t.Fatalf("valid encrypted message rejected: %v", err)
	}

	message.Ciphertext = nil
	if !errors.Is(message.Validate(), ErrInvalidMessage) {
		t.Fatal("message without ciphertext must be rejected")
	}
}

func TestCreateMessageRejectsUnknownKind(t *testing.T) {
	message := CreateMessage{
		ID:              "message-example",
		ConversationID:  "conversation-example",
		SenderID:        "account-example",
		ClientMessageID: "client-message-example",
		Kind:            "unknown",
		Ciphertext:      []byte("ciphertext-example"),
		Encryption: EncryptionMetadata{
			Scheme:  "mls_v1",
			GroupID: "group-example",
			Header:  []byte("header-example"),
		},
		CreatedAt: time.Date(2026, 7, 31, 8, 0, 0, 0, time.UTC),
	}
	if !errors.Is(message.Validate(), ErrInvalidMessage) {
		t.Fatal("unknown message kind must be rejected")
	}
}
