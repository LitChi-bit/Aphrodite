package migrations_test

import (
	"os"
	"strings"
	"testing"
)

func TestMLSProposalMigrationStoresOnlyOpaqueCoordinationMaterial(t *testing.T) {
	migration, err := os.ReadFile("000006_mls_proposals.up.sql")
	if err != nil {
		t.Fatalf("read MLS proposals migration: %v", err)
	}
	contents := string(migration)
	for _, required := range []string{
		"CREATE TABLE mls_proposals",
		"proposal_data bytea NOT NULL",
		"base_epoch bigint NOT NULL",
		"consumed_epoch bigint",
		"WHERE consumed_at IS NULL",
	} {
		if !strings.Contains(contents, required) {
			t.Fatalf("MLS proposal migration missing %q", required)
		}
	}
	for _, forbidden := range []string{"private_key", "group_secret", "plaintext", "decrypted_text"} {
		if strings.Contains(strings.ToLower(contents), forbidden) {
			t.Fatalf("MLS proposal migration must not persist %q", forbidden)
		}
	}
}
