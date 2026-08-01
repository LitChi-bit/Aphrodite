package migrations

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

var (
	ErrInvalidMigration = errors.New("invalid migration")
	ErrChecksumMismatch = errors.New("migration checksum mismatch")
)

var migrationNamePattern = regexp.MustCompile(`^(\d{6})_([a-z0-9_]+)\.up\.sql$`)
var createTablePattern = regexp.MustCompile(`(?im)CREATE\s+TABLE\s+([a-z_][a-z0-9_]*)`)

type Migration struct {
	Version        int64
	Name           string
	Path           string
	SQL            string
	Checksum       string
	RequiredTables []string
}

func Load(directory string) ([]Migration, error) {
	entries, err := os.ReadDir(directory)
	if err != nil {
		return nil, fmt.Errorf("read migration directory: %w", err)
	}
	migrations := make([]Migration, 0)
	versions := make(map[int64]string)
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		matches := migrationNamePattern.FindStringSubmatch(entry.Name())
		if matches == nil {
			continue
		}
		version, err := strconv.ParseInt(matches[1], 10, 64)
		if err != nil || version < 1 {
			return nil, fmt.Errorf("%w: %s", ErrInvalidMigration, entry.Name())
		}
		if previous, exists := versions[version]; exists {
			return nil, fmt.Errorf("%w: version %d used by %s and %s", ErrInvalidMigration, version, previous, entry.Name())
		}
		path := filepath.Join(directory, entry.Name())
		contents, err := os.ReadFile(path)
		if err != nil {
			return nil, fmt.Errorf("read migration %s: %w", entry.Name(), err)
		}
		sql, err := StripTransactionWrapper(string(contents))
		if err != nil {
			return nil, fmt.Errorf("%s: %w", entry.Name(), err)
		}
		hash := sha256.Sum256(contents)
		requiredTables := make([]string, 0)
		for _, tableMatch := range createTablePattern.FindAllStringSubmatch(sql, -1) {
			requiredTables = append(requiredTables, tableMatch[1])
		}
		migrations = append(migrations, Migration{
			Version: version, Name: matches[2], Path: path, SQL: sql,
			Checksum: hex.EncodeToString(hash[:]), RequiredTables: requiredTables,
		})
		versions[version] = entry.Name()
	}
	sort.Slice(migrations, func(i, j int) bool { return migrations[i].Version < migrations[j].Version })
	if len(migrations) == 0 {
		return nil, fmt.Errorf("%w: no up migrations found", ErrInvalidMigration)
	}
	return migrations, nil
}

func StripTransactionWrapper(sql string) (string, error) {
	normalized := strings.TrimSpace(sql)
	upper := strings.ToUpper(normalized)
	if !strings.HasPrefix(upper, "BEGIN;") || !strings.HasSuffix(upper, "COMMIT;") {
		return "", fmt.Errorf("%w: migration must use BEGIN/COMMIT wrapper", ErrInvalidMigration)
	}
	body := strings.TrimSpace(normalized[len("BEGIN;") : len(normalized)-len("COMMIT;")])
	if body == "" {
		return "", fmt.Errorf("%w: empty migration", ErrInvalidMigration)
	}
	return body, nil
}
