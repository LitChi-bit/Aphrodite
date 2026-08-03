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

func (repository *PostgresRepository) Commit(ctx context.Context, accountID, deviceID string, commit Commit) (GroupState, error) {
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
	if deviceID != commit.CommittedDeviceID {
		return GroupState{}, ErrInvalidCommit
	}
	var committedDeviceActive bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS (
		SELECT 1 FROM devices WHERE id = $1 AND account_id = $2 AND revoked_at IS NULL
	)`, deviceID, accountID).Scan(&committedDeviceActive); err != nil {
		return GroupState{}, fmt.Errorf("check committed MLS device: %w", err)
	}
	if !committedDeviceActive {
		return GroupState{}, ErrInvalidCommit
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
	if len(commit.ProposalIDs) > 0 {
		if commit.Epoch == 0 {
			return GroupState{}, ErrProposalConflict
		}
		result, err := tx.Exec(ctx, `UPDATE mls_proposals
			SET consumed_at = $3, consumed_epoch = $4
			WHERE conversation_id = $1 AND id = ANY($2) AND base_epoch = $4 - 1 AND consumed_at IS NULL`,
			commit.ConversationID, commit.ProposalIDs, commit.CommittedAt, commit.Epoch)
		if err != nil {
			return GroupState{}, fmt.Errorf("consume MLS proposals: %w", err)
		}
		if result.RowsAffected() != int64(len(commit.ProposalIDs)) {
			return GroupState{}, ErrProposalConflict
		}
	}
	result, err := tx.Exec(ctx, `INSERT INTO mls_device_roster (
		conversation_id, account_id, device_id, status, added_epoch, activated_epoch, created_at, activated_at
	) VALUES ($1,$2,$3,'active',$4,$4,$5,$5)
	ON CONFLICT (conversation_id, device_id) DO NOTHING`,
		commit.ConversationID, accountID, deviceID, commit.Epoch, commit.CommittedAt)
	if err != nil {
		return GroupState{}, fmt.Errorf("write committed MLS device roster: %w", err)
	}
	if result.RowsAffected() == 0 {
		var rosterAccountID, rosterStatus string
		if err := tx.QueryRow(ctx, `SELECT account_id, status FROM mls_device_roster
			WHERE conversation_id = $1 AND device_id = $2 FOR UPDATE`, commit.ConversationID, deviceID).Scan(&rosterAccountID, &rosterStatus); err != nil {
			return GroupState{}, fmt.Errorf("lock committed MLS device roster: %w", err)
		}
		if rosterAccountID != accountID || rosterStatus != "active" {
			return GroupState{}, ErrRosterConflict
		}
	}
	for _, deviceID := range commit.RemovedDevices {
		result, err := tx.Exec(ctx, `UPDATE mls_device_roster
			SET status = 'removed', removed_epoch = $3, removed_at = $4
			WHERE conversation_id = $1 AND device_id = $2 AND status = 'active'`,
			commit.ConversationID, deviceID, commit.Epoch, commit.CommittedAt)
		if err != nil {
			return GroupState{}, fmt.Errorf("remove MLS roster device: %w", err)
		}
		if result.RowsAffected() != 1 {
			return GroupState{}, ErrRosterConflict
		}
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
		result, err := tx.Exec(ctx, `INSERT INTO mls_device_roster (
			conversation_id, account_id, device_id, status, added_epoch, created_at
		) VALUES ($1,$2,$3,'pending',$4,$5)
		ON CONFLICT (conversation_id, device_id) DO UPDATE
		SET account_id = EXCLUDED.account_id, status = 'pending', added_epoch = EXCLUDED.added_epoch,
			activated_epoch = NULL, removed_epoch = NULL, created_at = EXCLUDED.created_at,
			activated_at = NULL, removed_at = NULL
		WHERE mls_device_roster.status = 'removed'`,
			commit.ConversationID, welcome.TargetAccountID, welcome.TargetDeviceID, commit.Epoch, commit.CommittedAt)
		if err != nil {
			return GroupState{}, fmt.Errorf("write MLS roster device: %w", err)
		}
		if result.RowsAffected() != 1 {
			return GroupState{}, ErrRosterConflict
		}
		_, err = tx.Exec(ctx, `INSERT INTO mls_welcome_deliveries (
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

func (repository *PostgresRepository) GetState(ctx context.Context, accountID, deviceID, conversationID string) (GroupState, error) {
	state, err := scanState(repository.pool.QueryRow(ctx, `SELECT state.conversation_id, state.epoch, state.group_info, state.commit_data, state.committed_by, state.committed_at
		FROM mls_group_states state
		JOIN conversation_members member ON member.conversation_id = state.conversation_id
		JOIN mls_device_roster roster ON roster.conversation_id = state.conversation_id
		WHERE state.conversation_id = $1 AND member.account_id = $2 AND member.left_at IS NULL
			AND roster.account_id = $2 AND roster.device_id = $3 AND roster.status = 'active'`, conversationID, accountID, deviceID))
	if errors.Is(err, pgx.ErrNoRows) {
		return GroupState{}, ErrNotFound
	}
	if err != nil {
		return GroupState{}, fmt.Errorf("read MLS state: %w", err)
	}
	return state, nil
}

func (repository *PostgresRepository) ListDeviceRoster(ctx context.Context, accountID, conversationID string) ([]DeviceRosterEntry, error) {
	var member bool
	if err := repository.pool.QueryRow(ctx, `SELECT EXISTS (
		SELECT 1 FROM conversation_members WHERE conversation_id = $1 AND account_id = $2 AND left_at IS NULL
	)`, conversationID, accountID).Scan(&member); err != nil {
		return nil, fmt.Errorf("check MLS roster member: %w", err)
	}
	if !member {
		return nil, ErrNotFound
	}
	rows, err := repository.pool.Query(ctx, `SELECT roster.conversation_id, roster.account_id, roster.device_id, roster.status,
		roster.added_epoch, roster.activated_epoch, roster.removed_epoch, roster.created_at, roster.activated_at, roster.removed_at
		FROM mls_device_roster roster
		WHERE roster.conversation_id = $1
		ORDER BY roster.created_at ASC, roster.device_id ASC`, conversationID)
	if err != nil {
		return nil, fmt.Errorf("list MLS device roster: %w", err)
	}
	defer rows.Close()
	entries := make([]DeviceRosterEntry, 0)
	for rows.Next() {
		var entry DeviceRosterEntry
		if err := rows.Scan(&entry.ConversationID, &entry.AccountID, &entry.DeviceID, &entry.Status,
			&entry.AddedEpoch, &entry.ActivatedEpoch, &entry.RemovedEpoch, &entry.CreatedAt, &entry.ActivatedAt, &entry.RemovedAt); err != nil {
			return nil, fmt.Errorf("scan MLS device roster: %w", err)
		}
		entries = append(entries, entry)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("read MLS device roster: %w", err)
	}
	return entries, nil
}

func (repository *PostgresRepository) PublishProposal(ctx context.Context, proposal Proposal) (Proposal, error) {
	if err := proposal.Validate(); err != nil {
		return Proposal{}, err
	}
	var currentEpoch int64
	err := repository.pool.QueryRow(ctx, `SELECT state.epoch FROM mls_group_states state
		JOIN mls_device_roster roster ON roster.conversation_id = state.conversation_id
		WHERE state.conversation_id = $1 AND roster.account_id = $2 AND roster.device_id = $3 AND roster.status = 'active'`,
		proposal.ConversationID, proposal.AuthorAccountID, proposal.AuthorDeviceID).Scan(&currentEpoch)
	if errors.Is(err, pgx.ErrNoRows) {
		return Proposal{}, ErrNotFound
	}
	if err != nil {
		return Proposal{}, fmt.Errorf("read MLS proposal epoch: %w", err)
	}
	if proposal.BaseEpoch != currentEpoch {
		return Proposal{}, ErrEpochConflict
	}
	_, err = repository.pool.Exec(ctx, `INSERT INTO mls_proposals (
		id, conversation_id, author_account_id, author_device_id, base_epoch, proposal_data, created_at
	) VALUES ($1,$2,$3,$4,$5,$6,$7)`, proposal.ID, proposal.ConversationID, proposal.AuthorAccountID,
		proposal.AuthorDeviceID, proposal.BaseEpoch, proposal.Data, proposal.CreatedAt)
	if err != nil {
		return Proposal{}, fmt.Errorf("write MLS proposal: %w", err)
	}
	return proposal, nil
}

func (repository *PostgresRepository) ListProposals(ctx context.Context, accountID, deviceID, conversationID string) ([]Proposal, error) {
	var active bool
	if err := repository.pool.QueryRow(ctx, `SELECT EXISTS (
		SELECT 1 FROM mls_device_roster WHERE conversation_id = $1 AND account_id = $2 AND device_id = $3 AND status = 'active'
	)`, conversationID, accountID, deviceID).Scan(&active); err != nil {
		return nil, fmt.Errorf("check MLS proposal roster: %w", err)
	}
	if !active {
		return nil, ErrNotFound
	}
	rows, err := repository.pool.Query(ctx, `SELECT proposal.id, proposal.conversation_id, proposal.author_account_id,
		proposal.author_device_id, proposal.base_epoch, proposal.proposal_data, proposal.created_at,
		proposal.consumed_at, proposal.consumed_epoch
		FROM mls_proposals proposal
		WHERE proposal.conversation_id = $1 AND proposal.consumed_at IS NULL
		ORDER BY proposal.created_at ASC, proposal.id ASC`, conversationID)
	if err != nil {
		return nil, fmt.Errorf("list MLS proposals: %w", err)
	}
	defer rows.Close()
	proposals := make([]Proposal, 0)
	for rows.Next() {
		var proposal Proposal
		if err := rows.Scan(&proposal.ID, &proposal.ConversationID, &proposal.AuthorAccountID, &proposal.AuthorDeviceID,
			&proposal.BaseEpoch, &proposal.Data, &proposal.CreatedAt, &proposal.ConsumedAt, &proposal.ConsumedEpoch); err != nil {
			return nil, fmt.Errorf("scan MLS proposal: %w", err)
		}
		proposals = append(proposals, proposal)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("read MLS proposals: %w", err)
	}
	return proposals, nil
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
		result, err := tx.Exec(ctx, `UPDATE mls_device_roster
			SET status = 'active', activated_epoch = $4, activated_at = now()
			WHERE conversation_id = $1 AND account_id = $2 AND device_id = $3 AND status = 'pending'`,
			delivery.ConversationID, accountID, deviceID, delivery.Epoch)
		if err != nil {
			return nil, fmt.Errorf("activate MLS roster device: %w", err)
		}
		if result.RowsAffected() != 1 {
			return nil, ErrRosterConflict
		}
		_, err = tx.Exec(ctx, `INSERT INTO conversation_members (conversation_id, account_id, role, joined_at)
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
