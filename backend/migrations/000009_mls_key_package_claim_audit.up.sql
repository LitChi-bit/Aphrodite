BEGIN;

ALTER TABLE mls_key_packages
    ADD COLUMN consumed_by_account_id uuid,
    ADD COLUMN consumed_by_device_id uuid,
    ADD COLUMN consumed_by_session_id uuid;

ALTER TABLE mls_key_packages
    ADD CONSTRAINT mls_key_packages_consumed_by_device_fk
        FOREIGN KEY (consumed_by_device_id, consumed_by_account_id)
        REFERENCES devices (id, account_id),
    ADD CONSTRAINT mls_key_packages_consumed_by_session_fk
        FOREIGN KEY (consumed_by_session_id)
        REFERENCES auth_sessions (id),
    ADD CONSTRAINT mls_key_packages_consumed_audit_complete_check
        CHECK (
            (consumed_at IS NULL AND consumed_by_account_id IS NULL AND consumed_by_device_id IS NULL AND consumed_by_session_id IS NULL)
            OR
            (consumed_at IS NOT NULL AND consumed_by_account_id IS NOT NULL AND consumed_by_device_id IS NOT NULL AND consumed_by_session_id IS NOT NULL)
        );

CREATE INDEX mls_key_packages_consumed_by_session_idx
    ON mls_key_packages (consumed_by_session_id)
    WHERE consumed_by_session_id IS NOT NULL;

COMMIT;
