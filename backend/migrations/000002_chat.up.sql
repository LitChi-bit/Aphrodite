BEGIN;

CREATE TABLE conversations (
    id uuid PRIMARY KEY,
    kind text NOT NULL CHECK (kind IN ('direct', 'group')),
    name text NOT NULL DEFAULT '',
    encryption_scheme text NOT NULL CHECK (char_length(encryption_scheme) BETWEEN 1 AND 64),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (char_length(name) <= 256)
);

CREATE TABLE conversation_members (
    conversation_id uuid NOT NULL REFERENCES conversations (id) ON DELETE CASCADE,
    account_id uuid NOT NULL REFERENCES accounts (id) ON DELETE CASCADE,
    role text NOT NULL DEFAULT 'member' CHECK (role IN ('member', 'admin')),
    joined_at timestamptz NOT NULL DEFAULT now(),
    left_at timestamptz,
    PRIMARY KEY (conversation_id, account_id),
    CHECK (left_at IS NULL OR left_at >= joined_at)
);

CREATE INDEX conversation_members_account_active_idx
    ON conversation_members (account_id, joined_at DESC)
    WHERE left_at IS NULL;

CREATE TABLE messages (
    id uuid PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES conversations (id) ON DELETE CASCADE,
    sender_id uuid NOT NULL REFERENCES accounts (id) ON DELETE RESTRICT,
    client_message_id uuid NOT NULL,
    kind text NOT NULL CHECK (kind IN ('text', 'image', 'video', 'audio', 'file', 'call', 'system')),
    ciphertext bytea NOT NULL CHECK (octet_length(ciphertext) > 0),
    encryption_scheme text NOT NULL CHECK (char_length(encryption_scheme) BETWEEN 1 AND 64),
    encryption_group_id text NOT NULL CHECK (char_length(encryption_group_id) BETWEEN 1 AND 256),
    encryption_epoch bigint NOT NULL CHECK (encryption_epoch >= 0),
    encryption_header bytea NOT NULL CHECK (octet_length(encryption_header) > 0),
    reply_to_message_id uuid,
    created_at timestamptz NOT NULL,
    edited_at timestamptz,
    deleted_at timestamptz,
    UNIQUE (id, conversation_id),
    UNIQUE (conversation_id, client_message_id),
    FOREIGN KEY (reply_to_message_id, conversation_id)
        REFERENCES messages (id, conversation_id) ON DELETE RESTRICT,
    CHECK (edited_at IS NULL OR edited_at >= created_at),
    CHECK (deleted_at IS NULL OR deleted_at >= created_at)
);

CREATE INDEX messages_conversation_created_idx
    ON messages (conversation_id, created_at DESC, id DESC);
CREATE INDEX messages_sender_client_idx
    ON messages (sender_id, client_message_id);

COMMIT;
