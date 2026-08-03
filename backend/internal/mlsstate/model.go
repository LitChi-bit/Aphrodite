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
	ErrRosterConflict   = errors.New("MLS device roster conflict")
	ErrInvalidProposal  = errors.New("invalid MLS proposal")
	ErrProposalConflict = errors.New("MLS proposal conflict")
)

// Commit and Welcome are opaque client-produced MLS bytes. The server never
// parses them or stores an MLS private key, group secret, or message plaintext.
type Commit struct {
	ConversationID    string
	CommittedDeviceID string
	Epoch             int64
	GroupInfo         []byte
	CommitData        []byte
	CommittedAt       time.Time
	Welcomes          []Welcome
	RemovedDevices    []string
	ProposalIDs       []string
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

type Proposal struct {
	ID              string
	ConversationID  string
	AuthorAccountID string
	AuthorDeviceID  string
	BaseEpoch       int64
	Data            []byte
	CreatedAt       time.Time
	ConsumedAt      *time.Time
	ConsumedEpoch   *int64
}

type DeviceRosterEntry struct {
	ConversationID string
	AccountID      string
	DeviceID       string
	Status         string
	AddedEpoch     int64
	ActivatedEpoch *int64
	RemovedEpoch   *int64
	CreatedAt      time.Time
	ActivatedAt    *time.Time
	RemovedAt      *time.Time
}

func (commit Commit) Validate() error {
	if strings.TrimSpace(commit.ConversationID) == "" || strings.TrimSpace(commit.CommittedDeviceID) == "" || commit.Epoch < 0 ||
		len(commit.GroupInfo) == 0 || len(commit.GroupInfo) > maxMaterialBytes ||
		len(commit.CommitData) == 0 || len(commit.CommitData) > maxMaterialBytes ||
		commit.CommittedAt.IsZero() || len(commit.Welcomes) > 20 {
		return ErrInvalidCommit
	}
	seenDevices := make(map[string]struct{}, len(commit.Welcomes)+len(commit.RemovedDevices))
	seenProposals := make(map[string]struct{}, len(commit.ProposalIDs))
	if len(commit.ProposalIDs) > 50 {
		return ErrInvalidCommit
	}
	for _, proposalID := range commit.ProposalIDs {
		if strings.TrimSpace(proposalID) == "" {
			return ErrInvalidCommit
		}
		if _, exists := seenProposals[proposalID]; exists {
			return ErrInvalidCommit
		}
		seenProposals[proposalID] = struct{}{}
	}
	for _, welcome := range commit.Welcomes {
		if err := welcome.Validate(); err != nil {
			return err
		}
		if _, exists := seenDevices[welcome.TargetDeviceID]; exists {
			return ErrInvalidCommit
		}
		seenDevices[welcome.TargetDeviceID] = struct{}{}
	}
	for _, deviceID := range commit.RemovedDevices {
		if strings.TrimSpace(deviceID) == "" {
			return ErrInvalidCommit
		}
		if _, exists := seenDevices[deviceID]; exists {
			return ErrInvalidCommit
		}
		seenDevices[deviceID] = struct{}{}
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
