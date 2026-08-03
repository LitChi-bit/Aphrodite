package migrations_test

import (
	"os"
	"strings"
	"testing"
)

func TestMLSProposalExpiryMigrationKeepsLifecycleExclusive(t *testing.T) {
	migration, err := os.ReadFile("000007_mls_proposal_expiry.up.sql")
	if err != nil {
		t.Fatalf("read MLS proposal expiry migration: %v", err)
	}
	contents := string(migration)
	for _, required := range []string{
		"ADD COLUMN expired_at timestamptz",
		"ADD COLUMN expired_epoch bigint",
		"expired_epoch > base_epoch",
		"consumed_at IS NULL AND expired_at IS NULL",
	} {
		if !strings.Contains(contents, required) {
			t.Fatalf("MLS proposal expiry migration missing %q", required)
		}
	}
}
