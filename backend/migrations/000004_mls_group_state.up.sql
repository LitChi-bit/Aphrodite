BEGIN;

CREATE TABLE mls_group_states (
    conversation_id uuid PRIMARY KEY REFERENCES conversations (id) ON DELETE CASCADE,
    epoch bigint NOT NULL CHECK (epoch >= 0),
    group_info bytea NOT NULL CHECK (octet_length(group_info) BETWEEN 1 AND 1048576),
    commit_data bytea NOT NULL CHECK (octet_length(commit_data) BETWEEN 1 AND 1048576),
    committed_by uuid NOT NULL REFERENCES accounts (id) ON DELETE RESTRICT,
    committed_at timestamptz NOT NULL
);

CREATE TABLE mls_welcome_deliveries (
    id uuid PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES conversations (id) ON DELETE CASCADE,
    epoch bigint NOT NULL CHECK (epoch >= 0),
    target_account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    target_device_id uuid NOT NULL,
    welcome_data bytea NOT NULL CHECK (octet_length(welcome_data) BETWEEN 1 AND 1048576),
    created_at timestamptz NOT NULL,
    claimed_at timestamptz,
    FOREIGN KEY (target_device_id, target_account_id)
        REFERENCES devices (id, account_id) ON DELETE CASCADE,
    UNIQUE (conversation_id, epoch, target_device_id),
    CHECK (claimed_at IS NULL OR claimed_at >= created_at)
);

CREATE INDEX mls_welcome_deliveries_target_pending_idx
    ON mls_welcome_deliveries (target_account_id, target_device_id, created_at ASC)
    WHERE claimed_at IS NULL;

COMMIT;
