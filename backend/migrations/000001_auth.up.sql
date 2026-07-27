BEGIN;

CREATE TABLE accounts (
    id uuid PRIMARY KEY,
    username text NOT NULL,
    email text NOT NULL,
    display_name text NOT NULL,
    password_hash text NOT NULL,
    status text NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'disabled')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (char_length(username) BETWEEN 3 AND 64),
    CHECK (char_length(display_name) BETWEEN 1 AND 128),
    CHECK (email = lower(email)),
    CHECK (password_hash <> '')
);

CREATE UNIQUE INDEX accounts_username_unique_ci
    ON accounts (lower(username));
CREATE UNIQUE INDEX accounts_email_unique
    ON accounts (email);

CREATE TABLE devices (
    id uuid PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    name text NOT NULL,
    platform text NOT NULL,
    identity_public_key bytea NOT NULL,
    last_seen_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (id, account_id),
    CHECK (char_length(name) BETWEEN 1 AND 128),
    CHECK (platform IN ('android', 'ios', 'windows', 'macos', 'linux', 'web')),
    CHECK (octet_length(identity_public_key) > 0)
);

CREATE INDEX devices_account_created_idx
    ON devices (account_id, created_at DESC);
CREATE INDEX devices_account_active_idx
    ON devices (account_id)
    WHERE revoked_at IS NULL;

CREATE TABLE login_challenges (
    id uuid PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    device_id uuid NOT NULL,
    device_name text NOT NULL,
    device_platform text NOT NULL,
    identity_public_key bytea NOT NULL,
    attempt_count smallint NOT NULL DEFAULT 0
        CHECK (attempt_count BETWEEN 0 AND 5),
    verified_at timestamptz,
    consumed_at timestamptz,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (id, account_id, device_id),
    CHECK (char_length(device_name) BETWEEN 1 AND 128),
    CHECK (device_platform IN ('android', 'ios', 'windows', 'macos', 'linux', 'web')),
    CHECK (octet_length(identity_public_key) > 0),
    CHECK (expires_at > created_at),
    CHECK (consumed_at IS NULL OR verified_at IS NOT NULL)
);

CREATE INDEX login_challenges_account_created_idx
    ON login_challenges (account_id, created_at DESC);
CREATE INDEX login_challenges_expiry_idx
    ON login_challenges (expires_at)
    WHERE consumed_at IS NULL;

CREATE TABLE authorization_codes (
    id uuid PRIMARY KEY,
    challenge_id uuid NOT NULL UNIQUE REFERENCES login_challenges (id) ON DELETE CASCADE,
    account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    device_id uuid NOT NULL,
    code_hash bytea NOT NULL,
    consumed_at timestamptz,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (challenge_id, account_id, device_id)
        REFERENCES login_challenges (id, account_id, device_id) ON DELETE CASCADE,
    CHECK (octet_length(code_hash) >= 32),
    CHECK (expires_at > created_at)
);

CREATE UNIQUE INDEX authorization_codes_hash_unique
    ON authorization_codes (code_hash);
CREATE INDEX authorization_codes_expiry_idx
    ON authorization_codes (expires_at)
    WHERE consumed_at IS NULL;

CREATE TABLE auth_sessions (
    id uuid PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    device_id uuid NOT NULL,
    revoked_at timestamptz,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (device_id, account_id)
        REFERENCES devices (id, account_id) ON DELETE CASCADE,
    CHECK (expires_at > created_at)
);

CREATE INDEX auth_sessions_account_created_idx
    ON auth_sessions (account_id, created_at DESC);
CREATE INDEX auth_sessions_device_active_idx
    ON auth_sessions (device_id)
    WHERE revoked_at IS NULL;

CREATE TABLE refresh_tokens (
    id uuid PRIMARY KEY,
    session_id uuid NOT NULL REFERENCES auth_sessions (id) ON DELETE CASCADE,
    token_hash bytea NOT NULL,
    replaced_by uuid,
    rotated_at timestamptz,
    revoked_at timestamptz,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (id, session_id),
    CHECK (octet_length(token_hash) >= 32),
    CHECK (expires_at > created_at),
    CHECK (replaced_by IS NULL OR replaced_by <> id),
    CHECK ((replaced_by IS NULL) = (rotated_at IS NULL)),
    FOREIGN KEY (replaced_by, session_id)
        REFERENCES refresh_tokens (id, session_id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX refresh_tokens_hash_unique
    ON refresh_tokens (token_hash);
CREATE INDEX refresh_tokens_session_created_idx
    ON refresh_tokens (session_id, created_at DESC);
CREATE INDEX refresh_tokens_expiry_active_idx
    ON refresh_tokens (expires_at)
    WHERE revoked_at IS NULL;

COMMIT;
