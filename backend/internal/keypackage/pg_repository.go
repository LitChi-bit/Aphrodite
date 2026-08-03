package keypackage

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const columns = `id, account_id, device_id, ciphersuite, key_package, signature, created_at, expires_at, consumed_at`
const packageColumns = `package.id, package.account_id, package.device_id, package.ciphersuite, package.key_package, package.signature, package.created_at, package.expires_at, package.consumed_at`

type PostgresRepository struct {
	pool *pgxpool.Pool
}

func NewPostgresRepository(pool *pgxpool.Pool) *PostgresRepository {
	return &PostgresRepository{pool: pool}
}

var _ Repository = (*PostgresRepository)(nil)

func (repository *PostgresRepository) Publish(ctx context.Context, accountID, deviceID string, items []Publish) error {
	if err := ValidatePublish(items); err != nil {
		return err
	}

	tx, err := repository.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin publish key packages: %w", err)
	}
	defer tx.Rollback(ctx)

	var activeDevice bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS (
		SELECT 1 FROM devices WHERE id = $1 AND account_id = $2 AND revoked_at IS NULL
	)`, deviceID, accountID).Scan(&activeDevice); err != nil {
		return fmt.Errorf("check publishing device: %w", err)
	}
	if !activeDevice {
		return ErrInvalidKeyPackage
	}

	for _, item := range items {
		_, err := tx.Exec(ctx, `INSERT INTO mls_key_packages (
			id, account_id, device_id, ciphersuite, key_package, signature, created_at, expires_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
		ON CONFLICT (id) DO NOTHING`, item.ID, accountID, deviceID, item.Ciphersuite, item.Package, item.Signature, item.CreatedAt, item.ExpiresAt)
		if err != nil {
			return fmt.Errorf("insert key package: %w", err)
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit publish key packages: %w", err)
	}
	return nil
}

func (repository *PostgresRepository) ListAvailable(ctx context.Context, accountID string, limit int, now time.Time) ([]KeyPackage, error) {
	if err := ValidateLimit(limit); err != nil {
		return nil, err
	}
	rows, err := repository.pool.Query(ctx, `SELECT `+packageColumns+`
		FROM mls_key_packages package
		JOIN devices device ON device.id = package.device_id AND device.account_id = package.account_id
		WHERE package.account_id = $1 AND package.consumed_at IS NULL AND package.expires_at > $2
		AND device.revoked_at IS NULL
		ORDER BY package.expires_at ASC, package.created_at ASC, package.id ASC
		LIMIT $3`, accountID, now, limit)
	if err != nil {
		return nil, fmt.Errorf("list key packages: %w", err)
	}
	defer rows.Close()
	return collect(rows)
}

func (repository *PostgresRepository) Claim(ctx context.Context, accountID string, limit int, now time.Time) ([]KeyPackage, error) {
	if err := ValidateLimit(limit); err != nil {
		return nil, err
	}
	tx, err := repository.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("begin claim key packages: %w", err)
	}
	defer tx.Rollback(ctx)

	rows, err := tx.Query(ctx, `WITH candidates AS (
		SELECT package.id
		FROM mls_key_packages package
		JOIN devices device ON device.id = package.device_id AND device.account_id = package.account_id
		WHERE package.account_id = $1 AND package.consumed_at IS NULL AND package.expires_at > $2
		AND device.revoked_at IS NULL
		ORDER BY package.expires_at ASC, package.created_at ASC, package.id ASC
		LIMIT $3
		FOR UPDATE OF package SKIP LOCKED
	), claimed AS (
		UPDATE mls_key_packages package
		SET consumed_at = $2
		FROM candidates
		WHERE package.id = candidates.id
		RETURNING `+columns+`
	)
	SELECT `+columns+` FROM claimed
	ORDER BY expires_at ASC, created_at ASC, id ASC`, accountID, now, limit)
	if err != nil {
		return nil, fmt.Errorf("claim key packages: %w", err)
	}
	items, err := collect(rows)
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("commit claim key packages: %w", err)
	}
	return items, nil
}

type rowScanner interface {
	Scan(...any) error
}

func collect(rows pgx.Rows) ([]KeyPackage, error) {
	defer rows.Close()
	items := make([]KeyPackage, 0)
	for rows.Next() {
		item, err := scan(rows)
		if err != nil {
			return nil, fmt.Errorf("scan key package: %w", err)
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("read key packages: %w", err)
	}
	return items, nil
}

func scan(row rowScanner) (KeyPackage, error) {
	var item KeyPackage
	if err := row.Scan(&item.ID, &item.AccountID, &item.DeviceID, &item.Ciphersuite, &item.Package, &item.Signature, &item.CreatedAt, &item.ExpiresAt, &item.ConsumedAt); err != nil {
		return KeyPackage{}, err
	}
	return item, nil
}
