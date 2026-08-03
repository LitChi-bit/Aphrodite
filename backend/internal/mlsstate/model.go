package mlsstate

import (
	"errors"
	"strings"
	"time"
)

const maxMaterialBytes = 1 << 20

var (
	ErrInvalidCommit    = errors.New("invalid MLS commit")
	ErrInvalidWelcome   = errors.New("invalid MLS welcome")
	ErrNotFound         = errors.New("MLS state not found")
	ErrNotAdministrator = errors.New("MLS commit requires administrator membership")
	ErrEpochConflict    = errors.New("MLS epoch conflict")
)

// Commit and Welcome are opaque client-produced MLS bytes. The server never
// parses them or stores an MLS private key, group secret, or message plaintext.
type Commit struct {
	ConversationID string
	Epoch          int64
	GroupInfo      []byte
	CommitData     []byte
	CommittedAt    time.Time
	Welcomes       []Welcome
}

type Welcome struct {
	ID              string
	TargetAccountID string
	TargetDeviceID  string
	Data            []byte
}

type GroupState struct {
	ConversationID string
	Epoch          int64
	GroupInfo      []byte
	CommitData     []byte
	CommittedBy    string
	CommittedAt    time.Time
}

type Delivery struct {
	ID             string
	ConversationID string
	Epoch          int64
	WelcomeData    []byte
	CreatedAt      time.Time
}

func (commit Commit) Validate() error {
	if strings.TrimSpace(commit.ConversationID) == "" || commit.Epoch < 0 ||
		len(commit.GroupInfo) == 0 || len(commit.GroupInfo) > maxMaterialBytes ||
		len(commit.CommitData) == 0 || len(commit.CommitData) > maxMaterialBytes ||
		commit.CommittedAt.IsZero() || len(commit.Welcomes) > 20 {
		return ErrInvalidCommit
	}
	seenDevices := make(map[string]struct{}, len(commit.Welcomes))
	for _, welcome := range commit.Welcomes {
		if err := welcome.Validate(); err != nil {
			return err
		}
		if _, exists := seenDevices[welcome.TargetDeviceID]; exists {
			return ErrInvalidCommit
		}
		seenDevices[welcome.TargetDeviceID] = struct{}{}
	}
	return nil
}

func (welcome Welcome) Validate() error {
	if strings.TrimSpace(welcome.ID) == "" || strings.TrimSpace(welcome.TargetAccountID) == "" ||
		strings.TrimSpace(welcome.TargetDeviceID) == "" || len(welcome.Data) == 0 || len(welcome.Data) > maxMaterialBytes {
		return ErrInvalidWelcome
	}
	return nil
}
