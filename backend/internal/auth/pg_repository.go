package auth

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// PostgresRepository is the PostgreSQL implementation of all auth repositories.
type PostgresRepository struct {
	pool *pgxpool.Pool
}

func NewPostgresRepository(pool *pgxpool.Pool) *PostgresRepository {
	return &PostgresRepository{pool: pool}
}

var (
	_ AccountRepository   = (*PostgresRepository)(nil)
	_ DeviceRepository    = (*PostgresRepository)(nil)
	_ ChallengeRepository = (*PostgresRepository)(nil)
	_ SessionRepository   = (*PostgresRepository)(nil)
)

const accountColumns = `id, username, email, display_name, password_hash, status, created_at, updated_at`
const deviceColumns = `id, account_id, name, platform, identity_public_key, last_seen_at, revoked_at, created_at, updated_at`
const challengeColumns = `id, account_id, device_id, device_name, device_platform, identity_public_key, attempt_count, verified_at, consumed_at, expires_at, created_at`
const codeColumns = `id, challenge_id, account_id, device_id, code_hash, consumed_at, expires_at, created_at`
const sessionColumns = `id, account_id, device_id, revoked_at, expires_at, created_at, updated_at`
const refreshTokenColumns = `id, session_id, token_hash, replaced_by, rotated_at, revoked_at, expires_at, created_at`

func (r *PostgresRepository) FindByLogin(ctx context.Context, login string) (Account, error) {
	row := r.pool.QueryRow(ctx, `SELECT `+accountColumns+` FROM accounts WHERE lower(username) = lower($1) OR email = lower($1)`, login)
	account, err := scanAccount(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return Account{}, ErrAccountNotFound
	}
	if err != nil {
		return Account{}, fmt.Errorf("find account by login: %w", err)
	}
	return account, nil
}

func (r *PostgresRepository) FindAccountByID(ctx context.Context, accountID string) (Account, error) {
	account, err := scanAccount(r.pool.QueryRow(ctx, `SELECT `+accountColumns+` FROM accounts WHERE id = $1`, accountID))
	if errors.Is(err, pgx.ErrNoRows) {
		return Account{}, ErrAccountNotFound
	}
	if err != nil {
		return Account{}, fmt.Errorf("find account by id: %w", err)
	}
	return account, nil
}

func (r *PostgresRepository) FindByID(ctx context.Context, deviceID string) (Device, error) {
	device, err := scanDevice(r.pool.QueryRow(ctx, `SELECT `+deviceColumns+` FROM devices WHERE id = $1`, deviceID))
	if errors.Is(err, pgx.ErrNoRows) {
		return Device{}, ErrDeviceNotFound
	}
	if err != nil {
		return Device{}, fmt.Errorf("find device by id: %w", err)
	}
	return device, nil
}

func (r *PostgresRepository) ListByAccount(ctx context.Context, accountID string) ([]Device, error) {
	rows, err := r.pool.Query(ctx, `SELECT `+deviceColumns+` FROM devices WHERE account_id = $1 ORDER BY created_at DESC`, accountID)
	if err != nil {
		return nil, fmt.Errorf("list devices by account: %w", err)
	}
	defer rows.Close()

	devices := make([]Device, 0)
	for rows.Next() {
		device, err := scanDevice(rows)
		if err != nil {
			return nil, fmt.Errorf("scan device: %w", err)
		}
		devices = append(devices, device)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list devices by account: %w", err)
	}
	return devices, nil
}

func (r *PostgresRepository) RevokeDevice(ctx context.Context, accountID, deviceID string) error {
	command, err := r.pool.Exec(ctx, `UPDATE devices SET revoked_at = COALESCE(revoked_at, now()), updated_at = now() WHERE id = $1 AND account_id = $2`, deviceID, accountID)
	if err != nil {
		return fmt.Errorf("revoke device: %w", err)
	}
	if command.RowsAffected() == 0 {
		return ErrDeviceNotFound
	}
	return nil
}

func (r *PostgresRepository) Create(ctx context.Context, challenge LoginChallenge) error {
	_, err := r.pool.Exec(ctx, `INSERT INTO login_challenges (`+challengeColumns+`) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
		challenge.ID, challenge.AccountID, challenge.DeviceID, challenge.DeviceName, challenge.DevicePlatform,
		challenge.IdentityPublicKey, challenge.AttemptCount, challenge.VerifiedAt, challenge.ConsumedAt,
		challenge.ExpiresAt, challenge.CreatedAt)
	if err != nil {
		return fmt.Errorf("create login challenge: %w", err)
	}
	return nil
}

func (r *PostgresRepository) AcquirePasswordAttempt(ctx context.Context, challengeID string, now time.Time) (LoginChallenge, error) {
	challenge, err := scanChallenge(r.pool.QueryRow(ctx, `UPDATE login_challenges
		SET attempt_count = attempt_count + 1
		WHERE id = $1 AND verified_at IS NULL AND consumed_at IS NULL AND expires_at > $2 AND attempt_count < 5
		RETURNING `+challengeColumns, challengeID, now))
	if err == nil {
		return challenge, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return LoginChallenge{}, fmt.Errorf("acquire password attempt: %w", err)
	}

	challenge, err = scanChallenge(r.pool.QueryRow(ctx, `SELECT `+challengeColumns+` FROM login_challenges WHERE id = $1`, challengeID))
	if errors.Is(err, pgx.ErrNoRows) {
		return LoginChallenge{}, ErrChallengeNotFound
	}
	if err != nil {
		return LoginChallenge{}, fmt.Errorf("read unavailable login challenge: %w", err)
	}
	if challenge.AttemptCount >= 5 {
		return LoginChallenge{}, ErrChallengeLocked
	}
	if !now.Before(challenge.ExpiresAt) || challenge.VerifiedAt != nil || challenge.ConsumedAt != nil {
		return LoginChallenge{}, ErrChallengeExpired
	}
	return LoginChallenge{}, ErrChallengeNotFound
}

func (r *PostgresRepository) VerifyRegisterDeviceAndCreateAuthorizationCode(ctx context.Context, challengeID string, now time.Time, code AuthorizationCode) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin verify challenge: %w", err)
	}
	defer tx.Rollback(ctx)

	challenge, err := scanChallenge(tx.QueryRow(ctx, `SELECT `+challengeColumns+` FROM login_challenges WHERE id = $1 FOR UPDATE`, challengeID))
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrChallengeNotFound
	}
	if err != nil {
		return fmt.Errorf("lock login challenge: %w", err)
	}
	if challenge.VerifiedAt != nil || challenge.ConsumedAt != nil || !now.Before(challenge.ExpiresAt) ||
		challenge.AttemptCount > 5 || challenge.AccountID != code.AccountID ||
		challenge.DeviceID != code.DeviceID || code.ChallengeID != challenge.ID {
		return ErrChallengeNotFound
	}

	var existingAccountID string
	var existingKey []byte
	err = tx.QueryRow(ctx, `SELECT account_id, identity_public_key FROM devices WHERE id = $1 FOR UPDATE`, challenge.DeviceID).Scan(&existingAccountID, &existingKey)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		_, err = tx.Exec(ctx, `INSERT INTO devices (id, account_id, name, platform, identity_public_key, created_at, updated_at) VALUES ($1,$2,$3,$4,$5,$6,$6)`, challenge.DeviceID, challenge.AccountID, challenge.DeviceName, challenge.DevicePlatform, challenge.IdentityPublicKey, now)
		if err != nil {
			return fmt.Errorf("create device: %w", err)
		}
	case err != nil:
		return fmt.Errorf("lock device: %w", err)
	case existingAccountID != challenge.AccountID || !equalBytes(existingKey, challenge.IdentityPublicKey):
		return ErrDeviceNotFound
	}

	if _, err := tx.Exec(ctx, `UPDATE login_challenges SET verified_at = $2 WHERE id = $1`, challenge.ID, now); err != nil {
		return fmt.Errorf("verify login challenge: %w", err)
	}
	if _, err := tx.Exec(ctx, `INSERT INTO authorization_codes (`+codeColumns+`) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`, code.ID, code.ChallengeID, code.AccountID, code.DeviceID, code.CodeHash, code.ConsumedAt, code.ExpiresAt, code.CreatedAt); err != nil {
		return fmt.Errorf("create authorization code: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit verified login challenge: %w", err)
	}
	return nil
}

func (r *PostgresRepository) ExchangeAuthorizationCode(ctx context.Context, codeHash []byte, deviceID string, now time.Time, session Session, refreshToken RefreshToken, accessExpiresAt time.Time) (AuthorizationCode, Session, RefreshToken, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return AuthorizationCode{}, Session{}, RefreshToken{}, fmt.Errorf("begin exchange authorization code: %w", err)
	}
	defer tx.Rollback(ctx)

	code, err := scanAuthorizationCode(tx.QueryRow(ctx, `SELECT `+codeColumns+` FROM authorization_codes WHERE code_hash = $1 FOR UPDATE`, codeHash))
	if errors.Is(err, pgx.ErrNoRows) || (err == nil && (!code.IsUsable(now) || code.DeviceID != deviceID)) {
		return AuthorizationCode{}, Session{}, RefreshToken{}, ErrAuthorizationCodeInvalid
	}
	if err != nil {
		return AuthorizationCode{}, Session{}, RefreshToken{}, fmt.Errorf("lock authorization code: %w", err)
	}

	account, err := scanAccount(tx.QueryRow(ctx, `SELECT `+accountColumns+` FROM accounts WHERE id = $1`, code.AccountID))
	if errors.Is(err, pgx.ErrNoRows) || (err == nil && account.Status != AccountStatusActive) {
		return AuthorizationCode{}, Session{}, RefreshToken{}, ErrAuthorizationCodeInvalid
	}
	if err != nil {
		return AuthorizationCode{}, Session{}, RefreshToken{}, fmt.Errorf("read authorization account: %w", err)
	}
	device, err := scanDevice(tx.QueryRow(ctx, `SELECT `+deviceColumns+` FROM devices WHERE id = $1 FOR UPDATE`, deviceID))
	if errors.Is(err, pgx.ErrNoRows) || (err == nil && (device.AccountID != code.AccountID || device.IsRevoked())) {
		return AuthorizationCode{}, Session{}, RefreshToken{}, ErrAuthorizationCodeInvalid
	}
	if err != nil {
		return AuthorizationCode{}, Session{}, RefreshToken{}, fmt.Errorf("lock authorization device: %w", err)
	}

	session.AccountID = code.AccountID
	refreshToken.SessionID = session.ID
	refreshToken.ExpiresAt = minTime(refreshToken.ExpiresAt, session.ExpiresAt)
	if _, err := tx.Exec(ctx, `UPDATE authorization_codes SET consumed_at = $2 WHERE id = $1`, code.ID, now); err != nil {
		return AuthorizationCode{}, Session{}, RefreshToken{}, fmt.Errorf("consume authorization code: %w", err)
	}
	if _, err := tx.Exec(ctx, `INSERT INTO auth_sessions (`+sessionColumns+`) VALUES ($1,$2,$3,$4,$5,$6,$7)`, session.ID, session.AccountID, session.DeviceID, session.RevokedAt, session.ExpiresAt, session.CreatedAt, session.UpdatedAt); err != nil {
		return AuthorizationCode{}, Session{}, RefreshToken{}, fmt.Errorf("create session: %w", err)
	}
	if _, err := tx.Exec(ctx, `INSERT INTO refresh_tokens (`+refreshTokenColumns+`) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`, refreshToken.ID, refreshToken.SessionID, refreshToken.TokenHash, refreshToken.ReplacedBy, refreshToken.RotatedAt, refreshToken.RevokedAt, refreshToken.ExpiresAt, refreshToken.CreatedAt); err != nil {
		return AuthorizationCode{}, Session{}, RefreshToken{}, fmt.Errorf("create refresh token: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return AuthorizationCode{}, Session{}, RefreshToken{}, fmt.Errorf("commit authorization exchange: %w", err)
	}
	return code, session, refreshToken, nil
}

func (r *PostgresRepository) RotateRefreshToken(ctx context.Context, currentTokenHash []byte, deviceID string, now time.Time, replacement RefreshToken, accessExpiresAt time.Time) (Session, RefreshToken, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return Session{}, RefreshToken{}, fmt.Errorf("begin rotate refresh token: %w", err)
	}
	defer tx.Rollback(ctx)

	current, err := scanRefreshToken(tx.QueryRow(ctx, `SELECT `+refreshTokenColumns+` FROM refresh_tokens WHERE token_hash = $1 FOR UPDATE`, currentTokenHash))
	if errors.Is(err, pgx.ErrNoRows) {
		return Session{}, RefreshToken{}, ErrRefreshTokenInvalid
	}
	if err != nil {
		return Session{}, RefreshToken{}, fmt.Errorf("lock refresh token: %w", err)
	}
	session, err := scanSession(tx.QueryRow(ctx, `SELECT `+sessionColumns+` FROM auth_sessions WHERE id = $1 FOR UPDATE`, current.SessionID))
	if errors.Is(err, pgx.ErrNoRows) {
		return Session{}, RefreshToken{}, ErrRefreshTokenInvalid
	}
	if err != nil {
		return Session{}, RefreshToken{}, fmt.Errorf("lock refresh session: %w", err)
	}

	valid := current.IsActive(now) && session.IsActive(now) && session.DeviceID == deviceID
	if valid {
		account, accountErr := scanAccount(tx.QueryRow(ctx, `SELECT `+accountColumns+` FROM accounts WHERE id = $1`, session.AccountID))
		device, deviceErr := scanDevice(tx.QueryRow(ctx, `SELECT `+deviceColumns+` FROM devices WHERE id = $1 FOR UPDATE`, deviceID))
		valid = accountErr == nil && account.Status == AccountStatusActive && deviceErr == nil && device.AccountID == session.AccountID && !device.IsRevoked()
		if accountErr != nil && !errors.Is(accountErr, pgx.ErrNoRows) {
			return Session{}, RefreshToken{}, fmt.Errorf("read refresh account: %w", accountErr)
		}
		if deviceErr != nil && !errors.Is(deviceErr, pgx.ErrNoRows) {
			return Session{}, RefreshToken{}, fmt.Errorf("lock refresh device: %w", deviceErr)
		}
	}
	if !valid {
		if _, err := tx.Exec(ctx, `UPDATE auth_sessions SET revoked_at = COALESCE(revoked_at, $2), updated_at = $2 WHERE id = $1`, session.ID, now); err != nil {
			return Session{}, RefreshToken{}, fmt.Errorf("revoke invalid refresh session: %w", err)
		}
		if err := tx.Commit(ctx); err != nil {
			return Session{}, RefreshToken{}, fmt.Errorf("commit invalid refresh session revoke: %w", err)
		}
		return Session{}, RefreshToken{}, ErrRefreshTokenInvalid
	}

	replacement.SessionID = session.ID
	replacement.ExpiresAt = minTime(replacement.ExpiresAt, session.ExpiresAt)
	// The self-referencing foreign key requires the replacement row first.
	if _, err := tx.Exec(ctx, `INSERT INTO refresh_tokens (`+refreshTokenColumns+`) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`, replacement.ID, replacement.SessionID, replacement.TokenHash, replacement.ReplacedBy, replacement.RotatedAt, replacement.RevokedAt, replacement.ExpiresAt, replacement.CreatedAt); err != nil {
		return Session{}, RefreshToken{}, fmt.Errorf("create replacement refresh token: %w", err)
	}
	if _, err := tx.Exec(ctx, `UPDATE refresh_tokens SET replaced_by = $2, rotated_at = $3 WHERE id = $1`, current.ID, replacement.ID, now); err != nil {
		return Session{}, RefreshToken{}, fmt.Errorf("replace refresh token: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return Session{}, RefreshToken{}, fmt.Errorf("commit refresh token rotation: %w", err)
	}
	return session, replacement, nil
}

func (r *PostgresRepository) FindActive(ctx context.Context, sessionID, accountID, deviceID string, now time.Time) (Session, error) {
	session, err := scanSession(r.pool.QueryRow(ctx, `SELECT `+sessionColumns+` FROM auth_sessions WHERE id = $1 AND account_id = $2 AND device_id = $3 AND revoked_at IS NULL AND expires_at > $4`, sessionID, accountID, deviceID, now))
	if errors.Is(err, pgx.ErrNoRows) {
		return Session{}, ErrSessionNotFound
	}
	if err != nil {
		return Session{}, fmt.Errorf("find active session: %w", err)
	}
	return session, nil
}

func (r *PostgresRepository) Revoke(ctx context.Context, sessionID string) error {
	command, err := r.pool.Exec(ctx, `UPDATE auth_sessions SET revoked_at = COALESCE(revoked_at, now()), updated_at = now() WHERE id = $1`, sessionID)
	if err != nil {
		return fmt.Errorf("revoke session: %w", err)
	}
	if command.RowsAffected() == 0 {
		return ErrSessionNotFound
	}
	return nil
}

func (r *PostgresRepository) RevokeByRefreshToken(ctx context.Context, tokenHash []byte, deviceID string, now time.Time) error {
	command, err := r.pool.Exec(ctx, `UPDATE auth_sessions AS s
		SET revoked_at = $3, updated_at = $3
		FROM refresh_tokens AS t
		WHERE t.token_hash = $1 AND t.session_id = s.id AND s.device_id = $2
			AND t.revoked_at IS NULL AND t.replaced_by IS NULL AND t.expires_at > $3
			AND s.revoked_at IS NULL AND s.expires_at > $3`, tokenHash, deviceID, now)
	if err != nil {
		return fmt.Errorf("revoke session by refresh token: %w", err)
	}
	if command.RowsAffected() == 0 {
		return ErrRefreshTokenInvalid
	}
	return nil
}

func (r *PostgresRepository) RevokeByDevice(ctx context.Context, accountID, deviceID string) error {
	_, err := r.pool.Exec(ctx, `UPDATE auth_sessions SET revoked_at = COALESCE(revoked_at, now()), updated_at = now() WHERE account_id = $1 AND device_id = $2`, accountID, deviceID)
	if err != nil {
		return fmt.Errorf("revoke sessions by device: %w", err)
	}
	return nil
}

func scanAccount(row pgx.Row) (Account, error) {
	var account Account
	err := row.Scan(&account.ID, &account.Username, &account.Email, &account.DisplayName, &account.PasswordHash, &account.Status, &account.CreatedAt, &account.UpdatedAt)
	return account, err
}

func scanDevice(row pgx.Row) (Device, error) {
	var device Device
	err := row.Scan(&device.ID, &device.AccountID, &device.Name, &device.Platform, &device.IdentityPublicKey, &device.LastSeenAt, &device.RevokedAt, &device.CreatedAt, &device.UpdatedAt)
	return device, err
}

func scanChallenge(row pgx.Row) (LoginChallenge, error) {
	var challenge LoginChallenge
	err := row.Scan(&challenge.ID, &challenge.AccountID, &challenge.DeviceID, &challenge.DeviceName, &challenge.DevicePlatform, &challenge.IdentityPublicKey, &challenge.AttemptCount, &challenge.VerifiedAt, &challenge.ConsumedAt, &challenge.ExpiresAt, &challenge.CreatedAt)
	return challenge, err
}

func scanAuthorizationCode(row pgx.Row) (AuthorizationCode, error) {
	var code AuthorizationCode
	err := row.Scan(&code.ID, &code.ChallengeID, &code.AccountID, &code.DeviceID, &code.CodeHash, &code.ConsumedAt, &code.ExpiresAt, &code.CreatedAt)
	return code, err
}

func scanSession(row pgx.Row) (Session, error) {
	var session Session
	err := row.Scan(&session.ID, &session.AccountID, &session.DeviceID, &session.RevokedAt, &session.ExpiresAt, &session.CreatedAt, &session.UpdatedAt)
	return session, err
}

func scanRefreshToken(row pgx.Row) (RefreshToken, error) {
	var token RefreshToken
	err := row.Scan(&token.ID, &token.SessionID, &token.TokenHash, &token.ReplacedBy, &token.RotatedAt, &token.RevokedAt, &token.ExpiresAt, &token.CreatedAt)
	return token, err
}

func equalBytes(left, right []byte) bool {
	if len(left) != len(right) {
		return false
	}
	var mismatch byte
	for i := range left {
		mismatch |= left[i] ^ right[i]
	}
	return mismatch == 0
}

func minTime(left, right time.Time) time.Time {
	if right.Before(left) {
		return right
	}
	return left
}
