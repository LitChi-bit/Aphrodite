BEGIN;

ALTER TABLE mls_proposals
    ADD COLUMN expired_at timestamptz,
    ADD COLUMN expired_epoch bigint CHECK (expired_epoch > base_epoch),
    ADD CHECK (
        (consumed_at IS NULL AND consumed_epoch IS NULL AND expired_at IS NULL AND expired_epoch IS NULL) OR
        (consumed_at IS NOT NULL AND consumed_epoch IS NOT NULL AND expired_at IS NULL AND expired_epoch IS NULL) OR
        (consumed_at IS NULL AND consumed_epoch IS NULL AND expired_at IS NOT NULL AND expired_epoch IS NOT NULL)
    );

DROP INDEX mls_proposals_conversation_pending_idx;
DROP INDEX mls_proposals_author_pending_idx;

CREATE INDEX mls_proposals_conversation_pending_idx
    ON mls_proposals (conversation_id, base_epoch, created_at ASC, id ASC)
    WHERE consumed_at IS NULL AND expired_at IS NULL;

CREATE INDEX mls_proposals_author_pending_idx
    ON mls_proposals (conversation_id, author_account_id, author_device_id, created_at ASC)
    WHERE consumed_at IS NULL AND expired_at IS NULL;

COMMIT;
