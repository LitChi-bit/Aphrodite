package chat

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const conversationColumns = `c.id, c.kind, c.name,
	COALESCE((SELECT array_agg(member.account_id::text ORDER BY member.account_id)
		FROM conversation_members member
		WHERE member.conversation_id = c.id AND member.left_at IS NULL), ARRAY[]::text[]),
	c.encryption_scheme, c.created_at, c.updated_at`
const messageColumns = `m.id, m.conversation_id, m.sender_id, m.client_message_id, m.kind, m.ciphertext, m.encryption_scheme, m.encryption_group_id, m.encryption_epoch, m.encryption_header, m.reply_to_message_id, m.created_at, m.edited_at, m.deleted_at`

type PostgresRepository struct {
	pool *pgxpool.Pool
}

func NewPostgresRepository(pool *pgxpool.Pool) *PostgresRepository {
	return &PostgresRepository{pool: pool}
}

var _ Repository = (*PostgresRepository)(nil)

func (r *PostgresRepository) ListConversations(ctx context.Context, accountID string, page Page) ([]Conversation, string, error) {
	if err := page.Validate(); err != nil {
		return nil, "", err
	}
	cursor, err := decodeCursor(page.Cursor)
	if err != nil {
		return nil, "", err
	}

	rows, err := r.pool.Query(ctx, `SELECT `+conversationColumns+`
		FROM conversations c
		JOIN conversation_members cm ON cm.conversation_id = c.id
		WHERE cm.account_id = $1 AND cm.left_at IS NULL
		AND ($2::timestamptz IS NULL OR (c.updated_at, c.id) < ($2, $3::uuid))
		ORDER BY c.updated_at DESC, c.id DESC
		LIMIT $4`, accountID, cursor.CreatedAt, nullableCursorID(cursor), page.Limit+1)
	if err != nil {
		return nil, "", fmt.Errorf("list conversations: %w", err)
	}
	defer rows.Close()

	conversations := make([]Conversation, 0, page.Limit+1)
	for rows.Next() {
		conversation, err := scanConversation(rows)
		if err != nil {
			return nil, "", fmt.Errorf("scan conversation: %w", err)
		}
		conversations = append(conversations, conversation)
	}
	if err := rows.Err(); err != nil {
		return nil, "", fmt.Errorf("list conversations: %w", err)
	}
	return conversationPage(conversations, page.Limit)
}

func (r *PostgresRepository) ListMessages(ctx context.Context, accountID, conversationID string, page Page) ([]Message, string, error) {
	if err := page.Validate(); err != nil {
		return nil, "", err
	}
	cursor, err := decodeCursor(page.Cursor)
	if err != nil {
		return nil, "", err
	}

	rows, err := r.pool.Query(ctx, `SELECT `+messageColumns+`
		FROM messages m
		JOIN conversation_members cm ON cm.conversation_id = m.conversation_id
		WHERE cm.account_id = $1 AND cm.left_at IS NULL AND m.conversation_id = $2
		AND ($3::timestamptz IS NULL OR (m.created_at, m.id) < ($3, $4::uuid))
		ORDER BY m.created_at DESC, m.id DESC
		LIMIT $5`, accountID, conversationID, cursor.CreatedAt, nullableCursorID(cursor), page.Limit+1)
	if err != nil {
		return nil, "", fmt.Errorf("list messages: %w", err)
	}
	defer rows.Close()

	messages := make([]Message, 0, page.Limit+1)
	for rows.Next() {
		message, err := scanMessage(rows)
		if err != nil {
			return nil, "", fmt.Errorf("scan message: %w", err)
		}
		messages = append(messages, message)
	}
	if err := rows.Err(); err != nil {
		return nil, "", fmt.Errorf("list messages: %w", err)
	}
	return messagePage(messages, page.Limit)
}

func (r *PostgresRepository) CreateMessage(ctx context.Context, accountID string, message CreateMessage) (Message, bool, error) {
	if err := message.Validate(); err != nil {
		return Message{}, false, err
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return Message{}, false, fmt.Errorf("begin create message: %w", err)
	}
	defer tx.Rollback(ctx)

	var memberExists bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS (
		SELECT 1 FROM conversation_members
		WHERE conversation_id = $1 AND account_id = $2 AND left_at IS NULL
	)`, message.ConversationID, accountID).Scan(&memberExists); err != nil {
		return Message{}, false, fmt.Errorf("check membership: %w", err)
	}
	if !memberExists || message.SenderID != accountID {
		return Message{}, false, ErrMembershipNotFound
	}

	if message.ReplyToMessageID != nil {
		var replyExists bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS (
			SELECT 1 FROM messages WHERE id = $1 AND conversation_id = $2
		)`, *message.ReplyToMessageID, message.ConversationID).Scan(&replyExists); err != nil {
			return Message{}, false, fmt.Errorf("check reply message: %w", err)
		}
		if !replyExists {
			return Message{}, false, ErrMessageNotFound
		}
	}

	created, err := scanMessage(tx.QueryRow(ctx, `INSERT INTO messages (
		id, conversation_id, sender_id, client_message_id, kind, ciphertext,
		encryption_scheme, encryption_group_id, encryption_epoch, encryption_header,
		reply_to_message_id, created_at
	) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
	ON CONFLICT (conversation_id, client_message_id) DO NOTHING
	RETURNING `+messageColumns,
		message.ID, message.ConversationID, message.SenderID, message.ClientMessageID,
		message.Kind, message.Ciphertext, message.Encryption.Scheme, message.Encryption.GroupID,
		message.Encryption.Epoch, message.Encryption.Header, message.ReplyToMessageID, message.CreatedAt))
	if errors.Is(err, pgx.ErrNoRows) {
		existing, err := scanMessage(tx.QueryRow(ctx, `SELECT `+messageColumns+`
			FROM messages WHERE conversation_id = $1 AND client_message_id = $2`,
			message.ConversationID, message.ClientMessageID))
		if err != nil {
			return Message{}, false, fmt.Errorf("read idempotent message: %w", err)
		}
		if existing.SenderID != accountID {
			return Message{}, false, ErrMembershipNotFound
		}
		if !matchesCreateMessage(existing, message) {
			return Message{}, false, ErrMessageConflict
		}
		return existing, true, tx.Commit(ctx)
	}
	if err != nil {
		return Message{}, false, fmt.Errorf("insert message: %w", err)
	}
	if _, err := tx.Exec(ctx, `UPDATE conversations SET updated_at = GREATEST(updated_at, $2) WHERE id = $1`, message.ConversationID, message.CreatedAt); err != nil {
		return Message{}, false, fmt.Errorf("touch conversation: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return Message{}, false, fmt.Errorf("commit message: %w", err)
	}
	return created, false, nil
}

type cursor struct {
	CreatedAt *time.Time `json:"created_at,omitempty"`
	ID        string     `json:"id,omitempty"`
}

func decodeCursor(encoded string) (cursor, error) {
	if encoded == "" {
		return cursor{}, nil
	}
	decoded, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil {
		return cursor{}, ErrInvalidPage
	}
	var decodedCursor cursor
	if err := json.Unmarshal(decoded, &decodedCursor); err != nil || decodedCursor.CreatedAt == nil || decodedCursor.ID == "" {
		return cursor{}, ErrInvalidPage
	}
	return decodedCursor, nil
}

func encodeCursor(createdAt time.Time, id string) string {
	encoded, _ := json.Marshal(cursor{CreatedAt: &createdAt, ID: id})
	return base64.RawURLEncoding.EncodeToString(encoded)
}

func nullableCursorID(cursor cursor) any {
	if cursor.CreatedAt == nil {
		return nil
	}
	return cursor.ID
}

func conversationPage(items []Conversation, limit int) ([]Conversation, string, error) {
	if len(items) <= limit {
		return items, "", nil
	}
	last := items[limit-1]
	return items[:limit], encodeCursor(last.UpdatedAt, last.ID), nil
}

func messagePage(items []Message, limit int) ([]Message, string, error) {
	if len(items) <= limit {
		return items, "", nil
	}
	last := items[limit-1]
	return items[:limit], encodeCursor(last.CreatedAt, last.ID), nil
}

type rowScanner interface {
	Scan(...any) error
}

func matchesCreateMessage(existing Message, candidate CreateMessage) bool {
	if existing.ConversationID != candidate.ConversationID || existing.SenderID != candidate.SenderID ||
		existing.ClientMessageID != candidate.ClientMessageID || existing.Kind != candidate.Kind ||
		string(existing.Ciphertext) != string(candidate.Ciphertext) ||
		existing.Encryption.Scheme != candidate.Encryption.Scheme ||
		existing.Encryption.GroupID != candidate.Encryption.GroupID ||
		existing.Encryption.Epoch != candidate.Encryption.Epoch ||
		string(existing.Encryption.Header) != string(candidate.Encryption.Header) {
		return false
	}
	if existing.ReplyToMessageID == nil || candidate.ReplyToMessageID == nil {
		return existing.ReplyToMessageID == nil && candidate.ReplyToMessageID == nil
	}
	return *existing.ReplyToMessageID == *candidate.ReplyToMessageID
}

func scanConversation(row rowScanner) (Conversation, error) {
	var conversation Conversation
	if err := row.Scan(&conversation.ID, &conversation.Kind, &conversation.Name, &conversation.ParticipantIDs, &conversation.EncryptionScheme, &conversation.CreatedAt, &conversation.UpdatedAt); err != nil {
		return Conversation{}, err
	}
	return conversation, nil
}

func scanMessage(row rowScanner) (Message, error) {
	var message Message
	if err := row.Scan(
		&message.ID, &message.ConversationID, &message.SenderID, &message.ClientMessageID,
		&message.Kind, &message.Ciphertext, &message.Encryption.Scheme, &message.Encryption.GroupID,
		&message.Encryption.Epoch, &message.Encryption.Header, &message.ReplyToMessageID,
		&message.CreatedAt, &message.EditedAt, &message.DeletedAt,
	); err != nil {
		return Message{}, err
	}
	return message, nil
}
