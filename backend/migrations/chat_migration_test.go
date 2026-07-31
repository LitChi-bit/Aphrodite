package migrations_test

import (
	"os"
	"strings"
	"testing"
)

func TestChatMigrationPreservesCiphertextOnlyAndMembershipConstraints(t *testing.T) {
	migration, err := os.ReadFile("000002_chat.up.sql")
	if err != nil {
		t.Fatalf("read chat migration: %v", err)
	}
	contents := string(migration)
	for _, required := range []string{
		"CREATE TABLE conversations",
		"CREATE TABLE conversation_members",
		"CREATE TABLE messages",
		"ciphertext bytea NOT NULL",
		"UNIQUE (conversation_id, client_message_id)",
		"FOREIGN KEY (reply_to_message_id, conversation_id)",
		"REFERENCES messages (id, conversation_id)",
	} {
		if !strings.Contains(contents, required) {
			t.Fatalf("chat migration missing %q", required)
		}
	}
	for _, forbidden := range []string{"plaintext", "decrypted_text"} {
		if strings.Contains(strings.ToLower(contents), forbidden) {
			t.Fatalf("chat migration must not persist %q", forbidden)
		}
	}
}
