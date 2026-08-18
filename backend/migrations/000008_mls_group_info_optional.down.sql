BEGIN;

ALTER TABLE mls_group_states
    ALTER COLUMN group_info SET NOT NULL;

COMMIT;
