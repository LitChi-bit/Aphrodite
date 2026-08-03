BEGIN;

CREATE TABLE mls_proposals (
    id uuid PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES conversations (id) ON DELETE CASCADE,
    author_account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    author_device_id uuid NOT NULL,
    base_epoch bigint NOT NULL CHECK (base_epoch >= 0),
    proposal_data bytea NOT NULL CHECK (octet_length(proposal_data) BETWEEN 1 AND 1048576),
    created_at timestamptz NOT NULL,
    consumed_at timestamptz,
    consumed_epoch bigint CHECK (consumed_epoch >= base_epoch),
    FOREIGN KEY (author_device_id, author_account_id)
        REFERENCES devices (id, account_id) ON DELETE CASCADE,
    CHECK ((consumed_at IS NULL AND consumed_epoch IS NULL) OR (consumed_at IS NOT NULL AND consumed_epoch IS NOT NULL))
);

CREATE INDEX mls_proposals_conversation_pending_idx
    ON mls_proposals (conversation_id, base_epoch, created_at ASC, id ASC)
    WHERE consumed_at IS NULL;

CREATE INDEX mls_proposals_author_pending_idx
    ON mls_proposals (conversation_id, author_account_id, author_device_id, created_at ASC)
    WHERE consumed_at IS NULL;

COMMIT;
