package migrations_test

import (
	"os"
	"strings"
	"testing"
)

func TestMLSDeviceRosterMigrationPreservesOpaqueMLSBoundary(t *testing.T) {
	migration, err := os.ReadFile("000005_mls_device_roster.up.sql")
	if err != nil {
		t.Fatalf("read MLS device roster migration: %v", err)
	}
	contents := string(migration)
	for _, required := range []string{
		"CREATE TABLE mls_device_roster",
		"status IN ('pending', 'active', 'removed')",
		"PRIMARY KEY (conversation_id, device_id)",
		"REFERENCES devices (id, account_id)",
		"WHERE status = 'active'",
	} {
		if !strings.Contains(contents, required) {
			t.Fatalf("MLS roster migration missing %q", required)
		}
	}
	for _, forbidden := range []string{"private_key", "group_secret", "plaintext", "decrypted_text", "welcome_data"} {
		if strings.Contains(strings.ToLower(contents), forbidden) {
			t.Fatalf("MLS roster migration must not persist %q", forbidden)
		}
	}
}
