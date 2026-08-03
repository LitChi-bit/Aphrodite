BEGIN;

DROP INDEX mls_proposals_author_pending_idx;
DROP INDEX mls_proposals_conversation_pending_idx;

ALTER TABLE mls_proposals
    DROP COLUMN expired_epoch,
    DROP COLUMN expired_at;

CREATE INDEX mls_proposals_conversation_pending_idx
    ON mls_proposals (conversation_id, base_epoch, created_at ASC, id ASC)
    WHERE consumed_at IS NULL;

CREATE INDEX mls_proposals_author_pending_idx
    ON mls_proposals (conversation_id, author_account_id, author_device_id, created_at ASC)
    WHERE consumed_at IS NULL;

COMMIT;
