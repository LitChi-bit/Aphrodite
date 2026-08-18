package mlsstate

import (
	"testing"
	"time"
)

func TestCommitAllowsEpochChangeWithoutWelcome(t *testing.T) {
	now := time.Date(2026, 8, 3, 0, 0, 0, 0, time.UTC)
	commit := Commit{ConversationID: "conversation-example", CommittedDeviceID: "device-example", Epoch: 1, GroupInfo: []byte{1}, CommitData: []byte{2}, CommittedAt: now}
	if err := commit.Validate(); err != nil {
		t.Fatalf("commit without welcome = %v", err)
	}
}

func TestCommitAllowsMissingGroupInfoButRejectsEmptyGroupInfo(t *testing.T) {
	now := time.Date(2026, 8, 3, 0, 0, 0, 0, time.UTC)
	valid := Commit{ConversationID: "conversation-example", CommittedDeviceID: "device-example", Epoch: 1, CommitData: []byte{2}, CommittedAt: now}
	if err := valid.Validate(); err != nil {
		t.Fatalf("commit without group info = %v", err)
	}
	empty := valid
	empty.GroupInfo = []byte{}
	if err := empty.Validate(); err != ErrInvalidCommit {
		t.Fatalf("commit with empty group info = %v", err)
	}
}

func TestCommitRejectsDuplicateWelcomeDevices(t *testing.T) {
	now := time.Date(2026, 8, 3, 0, 0, 0, 0, time.UTC)
	welcome := Welcome{ID: "welcome-example", TargetAccountID: "account-example", TargetDeviceID: "device-example", Data: []byte{1}}
	commit := Commit{ConversationID: "conversation-example", CommittedDeviceID: "device-example", Epoch: 1, GroupInfo: []byte{1}, CommitData: []byte{2}, CommittedAt: now, Welcomes: []Welcome{welcome, welcome}}
	if err := commit.Validate(); err != ErrInvalidCommit {
		t.Fatalf("duplicate welcome device = %v", err)
	}
}
