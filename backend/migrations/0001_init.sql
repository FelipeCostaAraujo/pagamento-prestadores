-- Diárias — initial schema.
--
-- Money is stored as integer cents (bigint) everywhere. Reais are a
-- presentation concern; keeping cents avoids binary-float rounding in JSON and
-- makes SUM() exact without depending on numeric arithmetic.

CREATE TABLE IF NOT EXISTS providers (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name               text     NOT NULL DEFAULT '',
    default_rate_cents bigint   NOT NULL DEFAULT 0 CHECK (default_rate_cents >= 0),
    -- Index into the app's fixed prestadora palette (see theme/tokens.dart).
    -- Each prestadora owns one colour; the calendar dots depend on it.
    color_index        smallint NOT NULL DEFAULT 0 CHECK (color_index >= 0),
    -- Manual ordering so the list keeps the order the user created them in.
    position           integer  NOT NULL DEFAULT 0,
    -- Soft delete: work entries and closings are history and must survive a
    -- prestadora being removed from the active list.
    archived_at        timestamptz,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS providers_active_idx
    ON providers (position, created_at)
    WHERE archived_at IS NULL;

-- One row per (prestadora, day) worked. The value defaults to the
-- prestadora's rate at insert time but is overridable per day, so it is
-- copied here rather than joined — a later rate change must not rewrite
-- history.
CREATE TABLE IF NOT EXISTS work_entries (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id uuid   NOT NULL REFERENCES providers (id) ON DELETE CASCADE,
    work_date   date   NOT NULL,
    value_cents bigint NOT NULL CHECK (value_cents >= 0),
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT work_entries_provider_date_key UNIQUE (provider_id, work_date)
);

-- Range scans by month drive the calendar and the closing screen.
CREATE INDEX IF NOT EXISTS work_entries_date_idx ON work_entries (work_date);
CREATE INDEX IF NOT EXISTS work_entries_provider_date_idx
    ON work_entries (provider_id, work_date);

-- A prestadora's month marked as paid. Absence of a row means "em aberto".
-- The amount is snapshotted so a later edit to the month cannot silently
-- change what was recorded as paid.
CREATE TABLE IF NOT EXISTS monthly_closings (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id       uuid     NOT NULL REFERENCES providers (id) ON DELETE CASCADE,
    period_year       smallint NOT NULL CHECK (period_year BETWEEN 1970 AND 4000),
    period_month      smallint NOT NULL CHECK (period_month BETWEEN 1 AND 12),
    paid_amount_cents bigint   NOT NULL CHECK (paid_amount_cents >= 0),
    paid_at           timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT monthly_closings_period_key
        UNIQUE (provider_id, period_year, period_month)
);

CREATE INDEX IF NOT EXISTS monthly_closings_period_idx
    ON monthly_closings (period_year, period_month);

-- Keep updated_at honest without relying on every writer to set it.
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER providers_set_updated_at
    BEFORE UPDATE ON providers
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE OR REPLACE TRIGGER work_entries_set_updated_at
    BEFORE UPDATE ON work_entries
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
