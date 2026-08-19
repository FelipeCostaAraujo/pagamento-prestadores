-- Username/password authentication.
--
-- Data stays shared: every authenticated user sees the same prestadoras and
-- diárias. There is deliberately no owner column on providers — this is one
-- household's calendar, and the login exists to keep the published API closed,
-- not to separate tenants.

CREATE TABLE IF NOT EXISTS users (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    username      text NOT NULL,
    -- argon2id, PHC string format ($argon2id$v=19$m=..,t=..,p=..$salt$hash).
    -- The parameters live in the string, so they can be raised later without a
    -- migration: an old hash keeps verifying with the values it was made with.
    password_hash text NOT NULL,
    -- Set to revoke access without deleting the row (and its sessions cascade).
    disabled_at   timestamptz,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Usernames are compared case-insensitively: "Felipe" and "felipe" are the same
-- account. Enforced by the database so a race between two admin commands cannot
-- create both.
CREATE UNIQUE INDEX IF NOT EXISTS users_username_lower_key
    ON users (lower(username));

-- One row per active login.
--
-- The token itself is never stored. Only its SHA-256 is, so a dump of this
-- table does not hand over working credentials. SHA-256 (not argon2) is right
-- here: the token is 256 bits of CSPRNG output, so there is nothing to brute
-- force, and lookups must stay fast — this runs on every request.
CREATE TABLE IF NOT EXISTS sessions (
    token_hash   bytea PRIMARY KEY,
    user_id      uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    expires_at   timestamptz NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    -- Free-form client hint ("Diárias Android"), to tell sessions apart when
    -- listing or revoking them.
    user_agent   text NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS sessions_user_idx ON sessions (user_id);
-- Supports the periodic sweep of expired rows.
CREATE INDEX IF NOT EXISTS sessions_expires_idx ON sessions (expires_at);

CREATE OR REPLACE TRIGGER users_set_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
