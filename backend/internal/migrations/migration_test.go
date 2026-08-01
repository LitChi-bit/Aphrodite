package migrations

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestLoadSortsMigrationsAndHashesOriginalContents(t *testing.T) {
	directory := t.TempDir()
	writeMigration(t, directory, "000002_chat.up.sql", "BEGIN;\nCREATE TABLE messages (id uuid);\nCOMMIT;\n")
	writeMigration(t, directory, "000001_auth.up.sql", "BEGIN;\nCREATE TABLE accounts (id uuid);\nCOMMIT;\n")

	migrations, err := Load(directory)
	if err != nil {
		t.Fatalf("load migrations: %v", err)
	}
	if len(migrations) != 2 || migrations[0].Version != 1 || migrations[1].Version != 2 {
		t.Fatalf("unexpected migration order: %#v", migrations)
	}
	if migrations[0].SQL != "CREATE TABLE accounts (id uuid);" || migrations[0].Checksum == "" {
		t.Fatalf("unexpected normalized migration: %#v", migrations[0])
	}
	if len(migrations[0].RequiredTables) != 1 || migrations[0].RequiredTables[0] != "accounts" {
		t.Fatalf("unexpected required tables: %#v", migrations[0].RequiredTables)
	}
}

func TestLoadRejectsDuplicateVersions(t *testing.T) {
	directory := t.TempDir()
	writeMigration(t, directory, "000001_auth.up.sql", "BEGIN;\nSELECT 1;\nCOMMIT;\n")
	writeMigration(t, directory, "000001_accounts.up.sql", "BEGIN;\nSELECT 2;\nCOMMIT;\n")

	_, err := Load(directory)
	if !errors.Is(err, ErrInvalidMigration) {
		t.Fatalf("duplicate version error = %v", err)
	}
}

func TestStripTransactionWrapperRejectsUnsafeMigration(t *testing.T) {
	for _, input := range []string{
		"SELECT 1;",
		"BEGIN;\nCOMMIT;",
		"BEGIN;\nSELECT 1;",
	} {
		if _, err := StripTransactionWrapper(input); !errors.Is(err, ErrInvalidMigration) {
			t.Fatalf("input %q error = %v", input, err)
		}
	}
}

func writeMigration(t *testing.T, directory, name, contents string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(directory, name), []byte(contents), 0o600); err != nil {
		t.Fatalf("write migration %s: %v", name, err)
	}
}
