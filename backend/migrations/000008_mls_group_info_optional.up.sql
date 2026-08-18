BEGIN;

ALTER TABLE mls_group_states
    ALTER COLUMN group_info DROP NOT NULL;

COMMIT;
