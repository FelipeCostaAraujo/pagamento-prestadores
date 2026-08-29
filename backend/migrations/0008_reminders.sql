-- Push reminders.
--
-- Two kinds, both of which need to know the current state of the data — "did
-- anyone record today?", "is last month paid?" — which is why they are sent by
-- the server rather than scheduled on the phone.

-- Devices that may receive a push. One row per install; the same account on two
-- phones gets two rows, and both are notified.
CREATE TABLE IF NOT EXISTS device_tokens (
    token        text PRIMARY KEY,
    user_id      uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    platform     text NOT NULL DEFAULT '',
    created_at   timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS device_tokens_user_idx ON device_tokens (user_id);

-- When someone is expected to work, so the app can ask whether the day was
-- recorded. Empty weekdays means no routine — the case for someone who comes
-- only when called.
ALTER TABLE providers
    ADD COLUMN IF NOT EXISTS remind_weekdays smallint[] NOT NULL DEFAULT '{}',
    -- Local time, in the timezone the server is configured with. Stored per
    -- provider because a cleaner leaving at 18h and a class ending at 21h do
    -- not share a sensible reminder hour.
    ADD COLUMN IF NOT EXISTS remind_at time NOT NULL DEFAULT '19:00';

DO $$
BEGIN
    -- 0 = Sunday .. 6 = Saturday, matching Go's time.Weekday.
    ALTER TABLE providers
        ADD CONSTRAINT providers_remind_weekdays_range
        CHECK (remind_weekdays <@ ARRAY[0,1,2,3,4,5,6]::smallint[]);
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- One row per reminder actually sent, so a scheduler that ticks every few
-- minutes — or restarts — cannot send the same reminder twice.
CREATE TABLE IF NOT EXISTS reminder_log (
    kind        text NOT NULL,
    -- Null for reminders that are not about one person, like the monthly
    -- payment nudge.
    provider_id uuid REFERENCES providers (id) ON DELETE CASCADE,
    due_on      date NOT NULL,
    sent_at     timestamptz NOT NULL DEFAULT now()
);

-- The uniqueness that makes the send idempotent. A partial index pair is needed
-- because NULL never equals NULL in a plain unique constraint.
CREATE UNIQUE INDEX IF NOT EXISTS reminder_log_provider_key
    ON reminder_log (kind, provider_id, due_on)
    WHERE provider_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS reminder_log_global_key
    ON reminder_log (kind, due_on)
    WHERE provider_id IS NULL;
