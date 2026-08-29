-- Refresh-token reuse detection.
--
-- Rotation alone only half-solves a stolen refresh token: the thief rotates,
-- the victim's next refresh fails, the victim signs in again — and the thief
-- keeps the rotated session until the 30-day deadline.
--
-- Keeping the hash of the token that was just consumed lets a replay be
-- recognised. A replay is strong evidence the credential leaked, so the whole
-- user's sessions are revoked rather than just failing the one request.

ALTER TABLE sessions
    ADD COLUMN IF NOT EXISTS previous_refresh_token_hash bytea;

-- Looked up only on the failure path, but that path is reachable by anyone
-- with a guess, so it must not be a sequential scan.
CREATE INDEX IF NOT EXISTS sessions_previous_refresh_hash_idx
    ON sessions (previous_refresh_token_hash)
    WHERE previous_refresh_token_hash IS NOT NULL;
