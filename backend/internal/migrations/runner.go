package migrations

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const advisoryLockKey int64 = 0x415048524f444954

type Applied struct {
	Version  int64
	Name     string
	Checksum string
}

type Runner struct {
	pool *pgxpool.Pool
	now  func() time.Time
}

func NewRunner(pool *pgxpool.Pool) *Runner {
	return &Runner{pool: pool, now: time.Now}
}

func (runner *Runner) Apply(ctx context.Context, migrations []Migration) error {
	connection, err := runner.pool.Acquire(ctx)
	if err != nil {
		return fmt.Errorf("acquire migration connection: %w", err)
	}
	defer connection.Release()
	if _, err := connection.Exec(ctx, `SELECT pg_advisory_lock($1)`, advisoryLockKey); err != nil {
		return fmt.Errorf("acquire migration lock: %w", err)
	}
	defer connection.Exec(context.Background(), `SELECT pg_advisory_unlock($1)`, advisoryLockKey)

	if _, err := connection.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
		version bigint PRIMARY KEY,
		name text NOT NULL,
		checksum text NOT NULL,
		applied_at timestamptz NOT NULL
	)`); err != nil {
		return fmt.Errorf("create schema migrations table: %w", err)
	}
	applied, err := readApplied(ctx, connection)
	if err != nil {
		return err
	}
	for _, migration := range migrations {
		if existing, ok := applied[migration.Version]; ok {
			if existing.Name != migration.Name || existing.Checksum != migration.Checksum {
				return fmt.Errorf("%w: version %d", ErrChecksumMismatch, migration.Version)
			}
			continue
		}
		if err := runner.applyOne(ctx, connection, migration); err != nil {
			return err
		}
	}
	return nil
}

func (runner *Runner) Baseline(ctx context.Context, migrations []Migration) error {
	connection, err := runner.pool.Acquire(ctx)
	if err != nil {
		return fmt.Errorf("acquire migration connection: %w", err)
	}
	defer connection.Release()
	if _, err := connection.Exec(ctx, `SELECT pg_advisory_lock($1)`, advisoryLockKey); err != nil {
		return fmt.Errorf("acquire migration lock: %w", err)
	}
	defer connection.Exec(context.Background(), `SELECT pg_advisory_unlock($1)`, advisoryLockKey)
	if _, err := connection.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
		version bigint PRIMARY KEY,
		name text NOT NULL,
		checksum text NOT NULL,
		applied_at timestamptz NOT NULL
	)`); err != nil {
		return fmt.Errorf("create schema migrations table: %w", err)
	}
	tx, err := connection.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin baseline: %w", err)
	}
	defer tx.Rollback(ctx)
	applied, err := readApplied(ctx, tx)
	if err != nil {
		return err
	}
	for _, migration := range migrations {
		if existing, ok := applied[migration.Version]; ok {
			if existing.Name != migration.Name || existing.Checksum != migration.Checksum {
				return fmt.Errorf("%w: version %d", ErrChecksumMismatch, migration.Version)
			}
			continue
		}
		for _, table := range migration.RequiredTables {
			var exists bool
			if err := tx.QueryRow(ctx, `SELECT to_regclass($1) IS NOT NULL`, "public."+table).Scan(&exists); err != nil {
				return fmt.Errorf("check baseline table %s: %w", table, err)
			}
			if !exists {
				return fmt.Errorf("baseline migration %d: required table %s is missing", migration.Version, table)
			}
		}
		if _, err := tx.Exec(ctx, `INSERT INTO schema_migrations (version, name, checksum, applied_at)
			VALUES ($1,$2,$3,$4)`, migration.Version, migration.Name, migration.Checksum, runner.now().UTC()); err != nil {
			return fmt.Errorf("baseline migration %d: %w", migration.Version, err)
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit baseline: %w", err)
	}
	return nil
}

func (runner *Runner) applyOne(ctx context.Context, connection *pgxpool.Conn, migration Migration) error {
	tx, err := connection.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin migration %d: %w", migration.Version, err)
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, migration.SQL); err != nil {
		return fmt.Errorf("apply migration %d: %w", migration.Version, err)
	}
	if _, err := tx.Exec(ctx, `INSERT INTO schema_migrations (version, name, checksum, applied_at) VALUES ($1,$2,$3,$4)`,
		migration.Version, migration.Name, migration.Checksum, runner.now().UTC()); err != nil {
		return fmt.Errorf("record migration %d: %w", migration.Version, err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit migration %d: %w", migration.Version, err)
	}
	return nil
}

type queryer interface {
	Query(context.Context, string, ...any) (pgx.Rows, error)
}

func readApplied(ctx context.Context, query queryer) (map[int64]Applied, error) {
	rows, err := query.Query(ctx, `SELECT version, name, checksum FROM schema_migrations ORDER BY version`)
	if err != nil {
		return nil, fmt.Errorf("read applied migrations: %w", err)
	}
	defer rows.Close()
	applied := make(map[int64]Applied)
	for rows.Next() {
		var item Applied
		if err := rows.Scan(&item.Version, &item.Name, &item.Checksum); err != nil {
			return nil, fmt.Errorf("scan applied migration: %w", err)
		}
		applied[item.Version] = item
	}
	if err := rows.Err(); err != nil && !errors.Is(err, context.Canceled) {
		return nil, fmt.Errorf("read applied migrations: %w", err)
	}
	return applied, nil
}
