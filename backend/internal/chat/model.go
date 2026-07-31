package chat

import (
	"errors"
	"strings"
	"time"
)

var (
	ErrInvalidPage          = errors.New("invalid page")
	ErrInvalidConversation  = errors.New("invalid conversation")
	ErrInvalidMessage       = errors.New("invalid message")
	ErrConversationNotFound = errors.New("conversation not found")
	ErrMembershipNotFound   = errors.New("conversation membership not found")
	ErrMessageNotFound      = errors.New("message not found")
	ErrMessageConflict      = errors.New("client message conflicts with existing message")
)

type ConversationKind string

const (
	ConversationKindDirect ConversationKind = "direct"
	ConversationKindGroup  ConversationKind = "group"
)

type MemberRole string

const (
	MemberRoleMember MemberRole = "member"
	MemberRoleAdmin  MemberRole = "admin"
)

type MessageKind string

const (
	MessageKindText   MessageKind = "text"
	MessageKindImage  MessageKind = "image"
	MessageKindVideo  MessageKind = "video"
	MessageKindAudio  MessageKind = "audio"
	MessageKindFile   MessageKind = "file"
	MessageKindCall   MessageKind = "call"
	MessageKindSystem MessageKind = "system"
)

type Conversation struct {
	ID               string
	Kind             ConversationKind
	Name             string
	ParticipantIDs   []string
	EncryptionScheme string
	CreatedAt        time.Time
	UpdatedAt        time.Time
}

type Member struct {
	ConversationID string
	AccountID      string
	Role           MemberRole
	JoinedAt       time.Time
	LeftAt         *time.Time
}

type EncryptionMetadata struct {
	Scheme  string
	GroupID string
	Epoch   int64
	Header  []byte
}

type Message struct {
	ID               string
	ConversationID   string
	SenderID         string
	ClientMessageID  string
	Kind             MessageKind
	Ciphertext       []byte
	Encryption       EncryptionMetadata
	ReplyToMessageID *string
	CreatedAt        time.Time
	EditedAt         *time.Time
	DeletedAt        *time.Time
}

type Page struct {
	Cursor string
	Limit  int
}

func (page Page) Validate() error {
	if page.Limit < 1 || page.Limit > 100 {
		return ErrInvalidPage
	}
	return nil
}

type CreateMessage struct {
	ID               string
	ConversationID   string
	SenderID         string
	ClientMessageID  string
	Kind             MessageKind
	Ciphertext       []byte
	Encryption       EncryptionMetadata
	ReplyToMessageID *string
	CreatedAt        time.Time
}

func (message CreateMessage) Validate() error {
	if message.ID == "" || message.ConversationID == "" || message.SenderID == "" ||
		message.ClientMessageID == "" || message.CreatedAt.IsZero() ||
		!validMessageKind(message.Kind) || len(message.Ciphertext) == 0 ||
		strings.TrimSpace(message.Encryption.Scheme) == "" ||
		strings.TrimSpace(message.Encryption.GroupID) == "" || message.Encryption.Epoch < 0 ||
		len(message.Encryption.Header) == 0 {
		return ErrInvalidMessage
	}
	return nil
}

func validMessageKind(kind MessageKind) bool {
	switch kind {
	case MessageKindText, MessageKindImage, MessageKindVideo, MessageKindAudio,
		MessageKindFile, MessageKindCall, MessageKindSystem:
		return true
	default:
		return false
	}
}
