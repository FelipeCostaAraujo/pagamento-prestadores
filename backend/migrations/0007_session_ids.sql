-- A public identifier for each session.
--
-- The primary key is the token digest, which must never leave the server:
-- handing it out would let anyone name — and revoke — a session they do not
-- hold. This opaque id is safe to show in the app's device list.
ALTER TABLE sessions
    ADD COLUMN IF NOT EXISTS id uuid NOT NULL DEFAULT gen_random_uuid();

CREATE UNIQUE INDEX IF NOT EXISTS sessions_id_key ON sessions (id);
