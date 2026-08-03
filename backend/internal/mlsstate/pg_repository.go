package mlsstate

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PostgresRepository struct{ pool *pgxpool.Pool }

func NewPostgresRepository(pool *pgxpool.Pool) *PostgresRepository {
	return &PostgresRepository{pool: pool}
}

var _ Repository = (*PostgresRepository)(nil)

func (repository *PostgresRepository) Commit(ctx context.Context, accountID string, commit Commit) (GroupState, error) {
	if err := commit.Validate(); err != nil {
		return GroupState{}, err
	}
	tx, err := repository.pool.Begin(ctx)
	if err != nil {
		return GroupState{}, fmt.Errorf("begin MLS commit: %w", err)
	}
	defer tx.Rollback(ctx)

	var lockedConversationID string
	err = tx.QueryRow(ctx, `SELECT id FROM conversations WHERE id = $1 FOR UPDATE`, commit.ConversationID).Scan(&lockedConversationID)
	if errors.Is(err, pgx.ErrNoRows) {
		return GroupState{}, ErrNotFound
	}
	if err != nil {
		return GroupState{}, fmt.Errorf("lock MLS conversation: %w", err)
	}

	var role string
	err = tx.QueryRow(ctx, `SELECT role FROM conversation_members WHERE conversation_id = $1 AND account_id = $2 AND left_at IS NULL FOR UPDATE`, commit.ConversationID, accountID).Scan(&role)
	if errors.Is(err, pgx.ErrNoRows) {
		return GroupState{}, ErrNotAdministrator
	}
	if err != nil {
		return GroupState{}, fmt.Errorf("lock commit member: %w", err)
	}
	if role != "admin" {
		return GroupState{}, ErrNotAdministrator
	}

	var currentEpoch int64
	err = tx.QueryRow(ctx, `SELECT epoch FROM mls_group_states WHERE conversation_id = $1 FOR UPDATE`, commit.ConversationID).Scan(&currentEpoch)
	if errors.Is(err, pgx.ErrNoRows) {
		if commit.Epoch != 0 {
			return GroupState{}, ErrEpochConflict
		}
	} else if err != nil {
		return GroupState{}, fmt.Errorf("lock MLS state: %w", err)
	} else if commit.Epoch != currentEpoch+1 {
		return GroupState{}, ErrEpochConflict
	}

	state, err := scanState(tx.QueryRow(ctx, `INSERT INTO mls_group_states (
		conversation_id, epoch, group_info, commit_data, committed_by, committed_at
	) VALUES ($1,$2,$3,$4,$5,$6)
	ON CONFLICT (conversation_id) DO UPDATE SET epoch = EXCLUDED.epoch, group_info = EXCLUDED.group_info,
		commit_data = EXCLUDED.commit_data, committed_by = EXCLUDED.committed_by, committed_at = EXCLUDED.committed_at
	RETURNING conversation_id, epoch, group_info, commit_data, committed_by, committed_at`,
		commit.ConversationID, commit.Epoch, commit.GroupInfo, commit.CommitData, accountID, commit.CommittedAt))
	if err != nil {
		return GroupState{}, fmt.Errorf("write MLS state: %w", err)
	}
	for _, welcome := range commit.Welcomes {
		var targetDeviceActive bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS (
			SELECT 1 FROM devices WHERE id = $1 AND account_id = $2 AND revoked_at IS NULL
		)`, welcome.TargetDeviceID, welcome.TargetAccountID).Scan(&targetDeviceActive); err != nil {
			return GroupState{}, fmt.Errorf("check MLS welcome target: %w", err)
		}
		if !targetDeviceActive {
			return GroupState{}, ErrInvalidWelcome
		}
		_, err := tx.Exec(ctx, `INSERT INTO mls_welcome_deliveries (
			id, conversation_id, epoch, target_account_id, target_device_id, welcome_data, created_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7)`, welcome.ID, commit.ConversationID, commit.Epoch, welcome.TargetAccountID, welcome.TargetDeviceID, welcome.Data, commit.CommittedAt)
		if err != nil {
			return GroupState{}, fmt.Errorf("write MLS welcome: %w", err)
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return GroupState{}, fmt.Errorf("commit MLS state: %w", err)
	}
	return state, nil
}

func (repository *PostgresRepository) GetState(ctx context.Context, accountID, conversationID string) (GroupState, error) {
	state, err := scanState(repository.pool.QueryRow(ctx, `SELECT state.conversation_id, state.epoch, state.group_info, state.commit_data, state.committed_by, state.committed_at
		FROM mls_group_states state JOIN conversation_members member ON member.conversation_id = state.conversation_id
		WHERE state.conversation_id = $1 AND member.account_id = $2 AND member.left_at IS NULL`, conversationID, accountID))
	if errors.Is(err, pgx.ErrNoRows) {
		return GroupState{}, ErrNotFound
	}
	if err != nil {
		return GroupState{}, fmt.Errorf("read MLS state: %w", err)
	}
	return state, nil
}

func (repository *PostgresRepository) ClaimWelcome(ctx context.Context, accountID, deviceID string) ([]Delivery, error) {
	tx, err := repository.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("begin welcome claim: %w", err)
	}
	defer tx.Rollback(ctx)
	rows, err := tx.Query(ctx, `WITH candidates AS (
		SELECT delivery.id FROM mls_welcome_deliveries delivery
		JOIN devices device ON device.id = delivery.target_device_id AND device.account_id = delivery.target_account_id
		WHERE delivery.target_account_id = $1 AND delivery.target_device_id = $2 AND delivery.claimed_at IS NULL AND device.revoked_at IS NULL
		ORDER BY delivery.created_at ASC, delivery.id ASC LIMIT 20 FOR UPDATE OF delivery SKIP LOCKED
	), claimed AS (
		UPDATE mls_welcome_deliveries delivery SET claimed_at = now() FROM candidates
		WHERE delivery.id = candidates.id
		RETURNING delivery.id, delivery.conversation_id, delivery.epoch, delivery.welcome_data, delivery.created_at
	)
	SELECT id, conversation_id, epoch, welcome_data, created_at FROM claimed ORDER BY created_at ASC, id ASC`, accountID, deviceID)
	if err != nil {
		return nil, fmt.Errorf("claim MLS welcome: %w", err)
	}
	defer rows.Close()
	deliveries := make([]Delivery, 0)
	for rows.Next() {
		var delivery Delivery
		if err := rows.Scan(&delivery.ID, &delivery.ConversationID, &delivery.Epoch, &delivery.WelcomeData, &delivery.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan MLS welcome: %w", err)
		}
		deliveries = append(deliveries, delivery)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("read MLS welcomes: %w", err)
	}
	for _, delivery := range deliveries {
		_, err := tx.Exec(ctx, `INSERT INTO conversation_members (conversation_id, account_id, role, joined_at)
			VALUES ($1,$2,'member',now()) ON CONFLICT (conversation_id, account_id) DO UPDATE SET left_at = NULL`, delivery.ConversationID, accountID)
		if err != nil {
			return nil, fmt.Errorf("activate MLS member: %w", err)
		}
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("commit welcome claim: %w", err)
	}
	return deliveries, nil
}

type scanner interface{ Scan(...any) error }

func scanState(row scanner) (GroupState, error) {
	var state GroupState
	if err := row.Scan(&state.ConversationID, &state.Epoch, &state.GroupInfo, &state.CommitData, &state.CommittedBy, &state.CommittedAt); err != nil {
		return GroupState{}, err
	}
	return state, nil
}
