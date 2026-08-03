BEGIN;

CREATE TABLE mls_key_packages (
    id uuid PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    device_id uuid NOT NULL,
    ciphersuite text NOT NULL CHECK (char_length(ciphersuite) BETWEEN 1 AND 128),
    key_package bytea NOT NULL CHECK (octet_length(key_package) BETWEEN 1 AND 65536),
    signature bytea NOT NULL CHECK (octet_length(signature) BETWEEN 1 AND 16384),
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    consumed_at timestamptz,
    FOREIGN KEY (device_id, account_id)
        REFERENCES devices (id, account_id) ON DELETE CASCADE,
    CHECK (expires_at > created_at),
    CHECK (consumed_at IS NULL OR consumed_at >= created_at)
);

CREATE INDEX mls_key_packages_available_idx
    ON mls_key_packages (account_id, expires_at ASC, created_at ASC, id ASC)
    WHERE consumed_at IS NULL;

COMMIT;
