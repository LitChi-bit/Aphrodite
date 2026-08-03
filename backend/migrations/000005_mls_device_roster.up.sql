BEGIN;

CREATE TABLE mls_device_roster (
    conversation_id uuid NOT NULL REFERENCES conversations (id) ON DELETE CASCADE,
    account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    device_id uuid NOT NULL,
    status text NOT NULL CHECK (status IN ('pending', 'active', 'removed')),
    added_epoch bigint NOT NULL CHECK (added_epoch >= 0),
    activated_epoch bigint CHECK (activated_epoch >= added_epoch),
    removed_epoch bigint CHECK (removed_epoch >= added_epoch),
    created_at timestamptz NOT NULL,
    activated_at timestamptz,
    removed_at timestamptz,
    PRIMARY KEY (conversation_id, device_id),
    FOREIGN KEY (device_id, account_id)
        REFERENCES devices (id, account_id) ON DELETE CASCADE,
    CHECK (
        (status = 'pending' AND activated_epoch IS NULL AND removed_epoch IS NULL AND activated_at IS NULL AND removed_at IS NULL) OR
        (status = 'active' AND activated_epoch IS NOT NULL AND removed_epoch IS NULL AND activated_at IS NOT NULL AND removed_at IS NULL) OR
        (status = 'removed' AND removed_epoch IS NOT NULL AND removed_at IS NOT NULL)
    )
);

CREATE INDEX mls_device_roster_conversation_active_idx
    ON mls_device_roster (conversation_id, account_id, device_id)
    WHERE status = 'active';

CREATE INDEX mls_device_roster_device_pending_idx
    ON mls_device_roster (account_id, device_id, created_at ASC)
    WHERE status = 'pending';

COMMIT;
