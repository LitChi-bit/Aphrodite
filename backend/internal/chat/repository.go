package chat

import "context"

// Repository persists ciphertext-only chat records. Every method receives the
// authenticated account ID so membership checks remain in the data boundary.
type Repository interface {
	ListConversations(ctx context.Context, accountID string, page Page) ([]Conversation, string, error)
	ListMessages(ctx context.Context, accountID, conversationID string, page Page) ([]Message, string, error)
	CreateMessage(ctx context.Context, accountID string, message CreateMessage) (Message, bool, error)
}
