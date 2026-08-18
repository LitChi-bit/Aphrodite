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

func TestMLSKeyPackageClaimAuditMigrationRecordsAuthenticatedCaller(t *testing.T) {
	migration, err := os.ReadFile("000009_mls_key_package_claim_audit.up.sql")
	if err != nil {
		t.Fatalf("read key package audit migration: %v", err)
	}
	contents := string(migration)
	for _, required := range []string{
		"consumed_by_account_id uuid",
		"consumed_by_device_id uuid",
		"consumed_by_session_id uuid",
		"REFERENCES devices (id, account_id)",
		"REFERENCES auth_sessions (id)",
		"consumed_audit_complete_check",
	} {
		if !strings.Contains(contents, required) {
			t.Fatalf("key package audit migration missing %q", required)
		}
	}
	for _, forbidden := range []string{"private_key", "group_secret", "plaintext", "decrypted_text"} {
		if strings.Contains(strings.ToLower(contents), forbidden) {
			t.Fatalf("key package audit migration must not persist %q", forbidden)
		}
	}
}

func TestMLSGroupInfoOptionalMigrationOnlyRelaxesNullability(t *testing.T) {
	migration, err := os.ReadFile("000008_mls_group_info_optional.up.sql")
	if err != nil {
		t.Fatalf("read optional group info migration: %v", err)
	}
	contents := string(migration)
	if !strings.Contains(contents, "ALTER COLUMN group_info DROP NOT NULL") {
		t.Fatal("optional group info migration must allow SQL NULL")
	}
	if strings.Contains(contents, "DROP CONSTRAINT") || strings.Contains(contents, "DROP CHECK") {
		t.Fatal("optional group info migration must retain non-empty material validation")
	}
	down, err := os.ReadFile("000008_mls_group_info_optional.down.sql")
	if err != nil {
		t.Fatalf("read optional group info down migration: %v", err)
	}
	if !strings.Contains(string(down), "ALTER COLUMN group_info SET NOT NULL") {
		t.Fatal("optional group info down migration must restore nullability")
	}
}
