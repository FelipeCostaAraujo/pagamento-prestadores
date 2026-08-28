-- Short-lived access tokens plus rotating refresh tokens.
--
-- Existing sessions intentionally keep refresh_token_hash NULL. Their current
-- bearer token remains valid until its original expiry, after which the user
-- signs in once to receive the new token pair.

ALTER TABLE sessions
    ADD COLUMN IF NOT EXISTS refresh_token_hash bytea,
    ADD COLUMN IF NOT EXISTS refresh_expires_at timestamptz;

CREATE UNIQUE INDEX IF NOT EXISTS sessions_refresh_token_hash_key
    ON sessions (refresh_token_hash)
    WHERE refresh_token_hash IS NOT NULL;

-- Supports both refresh lookup/expiry and the periodic session sweep.
CREATE INDEX IF NOT EXISTS sessions_refresh_expires_idx
    ON sessions (refresh_expires_at)
    WHERE refresh_expires_at IS NOT NULL;
