BEGIN;

DROP INDEX IF EXISTS mls_key_packages_consumed_by_session_idx;
ALTER TABLE mls_key_packages
    DROP CONSTRAINT IF EXISTS mls_key_packages_consumed_audit_complete_check,
    DROP CONSTRAINT IF EXISTS mls_key_packages_consumed_by_session_fk,
    DROP CONSTRAINT IF EXISTS mls_key_packages_consumed_by_device_fk,
    DROP COLUMN IF EXISTS consumed_by_session_id,
    DROP COLUMN IF EXISTS consumed_by_device_id,
    DROP COLUMN IF EXISTS consumed_by_account_id;

COMMIT;
