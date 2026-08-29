package store

import (
	"context"
	"fmt"
	"time"

	"github.com/felipearaujo/diarias/backend/internal/domain"
)

// Reminder kinds, as stored in reminder_log.
const (
	ReminderWork    = "work"
	ReminderPayment = "payment"
)

// RegisterDevice records a push token for a user, or moves it if the same
// install signed in as someone else.
//
// The token is the primary key rather than (user, token): FCM hands the same
// string back to whoever installs the app, so a token must belong to exactly
// one account at a time or one person's reminders would reach another's phone.
func (s *Store) RegisterDevice(ctx context.Context, userID, token, platform string) error {
	if token == "" {
		return domain.Invalid("token is required")
	}
	if len(platform) > 40 {
		platform = platform[:40]
	}
	_, err := s.pool.Exec(ctx, `
		INSERT INTO device_tokens (token, user_id, platform)
		VALUES ($1, $2, $3)
		ON CONFLICT (token) DO UPDATE
			SET user_id = EXCLUDED.user_id,
			    platform = EXCLUDED.platform,
			    last_seen_at = now()`,
		token, userID, platform)
	if err != nil {
		return fmt.Errorf("register device: %w", err)
	}
	return nil
}

// UnregisterDevice drops a token, on logout or when FCM reports it dead.
func (s *Store) UnregisterDevice(ctx context.Context, token string) error {
	_, err := s.pool.Exec(ctx,
		`DELETE FROM device_tokens WHERE token = $1`, token)
	if err != nil {
		return fmt.Errorf("unregister device: %w", err)
	}
	return nil
}

// AllDeviceTokens returns every token that should receive household reminders.
//
// The data is shared, so reminders go to everyone signed in: whoever acts on it
// first settles it for the rest.
func (s *Store) AllDeviceTokens(ctx context.Context) ([]string, error) {
	rows, err := s.pool.Query(ctx, `SELECT token FROM device_tokens`)
	if err != nil {
		return nil, fmt.Errorf("list device tokens: %w", err)
	}
	defer rows.Close()

	tokens := make([]string, 0, 4)
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err != nil {
			return nil, fmt.Errorf("scan token: %w", err)
		}
		tokens = append(tokens, t)
	}
	return tokens, rows.Err()
}

// DueWorkReminders returns the people who were expected today, whose reminder
// time has passed, and whose day nobody has recorded yet.
//
// All three conditions are evaluated in one statement so the scheduler cannot
// act on a state that changed between queries. `now` is the current time in the
// household's timezone; the date and clock time are taken from it.
func (s *Store) DueWorkReminders(ctx context.Context, now time.Time) ([]domain.Provider, error) {
	today := domain.NewDate(now.Year(), now.Month(), now.Day())
	weekday := int(now.Weekday())
	clock := now.Format("15:04")

	rows, err := s.pool.Query(ctx, `
		SELECT `+providerCols+`
		FROM providers p
		WHERE p.archived_at IS NULL
		  AND $2::smallint = ANY(p.remind_weekdays)
		  AND p.remind_at <= $3::time
		  -- Already recorded: nothing to ask about. Any kind counts, including
		  -- a falta — the point is that someone decided, not that she worked.
		  AND NOT EXISTS (
			SELECT 1 FROM work_entries e
			WHERE e.provider_id = p.id AND e.work_date = $1::date
		  )
		  -- Already asked today.
		  AND NOT EXISTS (
			SELECT 1 FROM reminder_log l
			WHERE l.kind = 'work' AND l.provider_id = p.id AND l.due_on = $1::date
		  )
		ORDER BY p.position`,
		today.Time, weekday, clock)
	if err != nil {
		return nil, fmt.Errorf("due work reminders: %w", err)
	}
	defer rows.Close()

	providers := make([]domain.Provider, 0, 4)
	for rows.Next() {
		p, err := scanProvider(rows)
		if err != nil {
			return nil, fmt.Errorf("scan provider: %w", err)
		}
		providers = append(providers, p)
	}
	return providers, rows.Err()
}

// UnpaidPrevious reports who still has an open month for the period before
// [now], and how much is owed in total.
//
// Used for the payment nudge: on payday, anyone who worked last month and has
// not been marked as paid.
func (s *Store) UnpaidPrevious(ctx context.Context, now time.Time) ([]string, int64, error) {
	period := previousPeriod(now)
	closing, err := s.MonthClosing(ctx, period)
	if err != nil {
		return nil, 0, err
	}

	var names []string
	var owed int64
	for _, pc := range closing.Providers {
		if pc.Paid || pc.EntryCount == 0 {
			continue
		}
		names = append(names, pc.Provider.Name)
		owed += pc.TotalCents
	}
	return names, owed, nil
}

// previousPeriod is the month before the one containing now.
func previousPeriod(now time.Time) domain.Period {
	year, month := now.Year(), int(now.Month())
	month--
	if month == 0 {
		month = 12
		year--
	}
	return domain.Period{Year: year, Month: month}
}

// MarkReminderSent records a reminder so it is not repeated.
//
// Returns false when the row already existed, which is how two schedulers — or
// one restarting mid-tick — avoid sending twice. Callers should claim the
// reminder before sending, not after: a duplicate push is worse than a missed
// log entry.
func (s *Store) MarkReminderSent(ctx context.Context, kind string, providerID *string, dueOn domain.Date) (bool, error) {
	tag, err := s.pool.Exec(ctx, `
		INSERT INTO reminder_log (kind, provider_id, due_on)
		VALUES ($1, $2, $3)
		ON CONFLICT DO NOTHING`,
		kind, providerID, dueOn.Time)
	if err != nil {
		return false, fmt.Errorf("mark reminder sent: %w", err)
	}
	return tag.RowsAffected() == 1, nil
}

// ReleaseReminder undoes a claim, so a send that failed for a transient reason
// is tried again on the next tick instead of being silently swallowed.
func (s *Store) ReleaseReminder(ctx context.Context, kind string, providerID *string, dueOn domain.Date) {
	_, _ = s.pool.Exec(ctx, `
		DELETE FROM reminder_log
		WHERE kind = $1 AND due_on = $3
		  AND provider_id IS NOT DISTINCT FROM $2`,
		kind, providerID, dueOn.Time)
}
