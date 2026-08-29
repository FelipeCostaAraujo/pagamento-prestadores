-- Half days and absences.
--
-- A worked day used to be the only thing worth recording. Two more cases show
-- up in practice: she worked half a day, and she was expected but did not come.
-- Both belong on the calendar; only the first two are owed money.
--
-- Existing rows are full days, which is what they always meant.

ALTER TABLE work_entries
    ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'full';

DO $$
BEGIN
    ALTER TABLE work_entries
        ADD CONSTRAINT work_entries_kind_check
        CHECK (kind IN ('full', 'half', 'absence'));
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- An absence is a record that nothing is owed. Keeping the invariant here means
-- no code path can quietly bill for one.
DO $$
BEGIN
    ALTER TABLE work_entries
        ADD CONSTRAINT work_entries_absence_is_free
        CHECK (kind <> 'absence' OR value_cents = 0);
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;
