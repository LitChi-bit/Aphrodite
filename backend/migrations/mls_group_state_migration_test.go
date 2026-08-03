package migrations_test

import (
	"os"
	"strings"
	"testing"
)

func TestMLSGroupStateMigrationPreservesOpaqueMaterialsAndWelcomeIsolation(t *testing.T) {
	migration, err := os.ReadFile("000004_mls_group_state.up.sql")
	if err != nil {
		t.Fatalf("read MLS state migration: %v", err)
	}
	contents := string(migration)
	for _, required := range []string{
		"CREATE TABLE mls_group_states",
		"CREATE TABLE mls_welcome_deliveries",
		"group_info bytea NOT NULL",
		"commit_data bytea NOT NULL",
		"welcome_data bytea NOT NULL",
		"UNIQUE (conversation_id, epoch, target_device_id)",
		"WHERE claimed_at IS NULL",
	} {
		if !strings.Contains(contents, required) {
			t.Fatalf("MLS migration missing %q", required)
		}
	}
	for _, forbidden := range []string{"private_key", "group_secret", "plaintext", "decrypted_text"} {
		if strings.Contains(strings.ToLower(contents), forbidden) {
			t.Fatalf("MLS migration must not persist %q", forbidden)
		}
	}
}
