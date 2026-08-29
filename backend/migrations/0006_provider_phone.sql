-- Phone number per prestadora, so the closing message can actually be sent.
--
-- Stored as the user typed it. Normalisation to E.164 happens in the app when
-- building the wa.me link: keeping the original means a number that was entered
-- oddly can still be read and corrected by a human.
ALTER TABLE providers
    ADD COLUMN IF NOT EXISTS phone text NOT NULL DEFAULT '';
