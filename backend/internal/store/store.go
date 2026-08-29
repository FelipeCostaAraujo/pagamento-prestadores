// Package store implements persistence for the Diárias domain on Postgres.
package store

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/felipearaujo/diarias/backend/internal/domain"
)

// PaletteSize is the number of prestadora colours the app cycles through. It
// mirrors the palette in the Flutter theme (app/lib/theme/tokens.dart); the
// backend only stores the index.
const PaletteSize = 4

type Store struct{ pool *pgxpool.Pool }

func New(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

const providerCols = `id, name, default_rate_cents, color_index, position, phone,
	remind_weekdays, to_char(remind_at, 'HH24:MI'), created_at, updated_at`

func scanProvider(row pgx.Row) (domain.Provider, error) {
	var p domain.Provider
	err := row.Scan(&p.ID, &p.Name, &p.DefaultRateCents, &p.ColorIndex,
		&p.Position, &p.Phone, &p.RemindWeekdays, &p.RemindAt,
		&p.CreatedAt, &p.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Provider{}, domain.ErrNotFound
	}
	if err != nil {
		return domain.Provider{}, err
	}
	return p, nil
}

// ListProviders returns the active prestadoras in display order.
func (s *Store) ListProviders(ctx context.Context) ([]domain.Provider, error) {
	rows, err := s.pool.Query(ctx, `SELECT `+providerCols+`
		FROM providers
		WHERE archived_at IS NULL
		ORDER BY position, created_at`)
	if err != nil {
		return nil, fmt.Errorf("list providers: %w", err)
	}
	defer rows.Close()

	// Non-nil so an empty list serialises as [] rather than null.
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

func (s *Store) GetProvider(ctx context.Context, id string) (domain.Provider, error) {
	return scanProvider(s.pool.QueryRow(ctx, `SELECT `+providerCols+`
		FROM providers WHERE id = $1 AND archived_at IS NULL`, id))
}

// CreateProvider adds a prestadora. A nil colorIndex picks the lowest colour
// not already taken by an active prestadora, so two people in a short list
// never share a calendar dot colour.
func (s *Store) CreateProvider(ctx context.Context, name string, rateCents int64, colorIndex *int) (domain.Provider, error) {
	name = strings.TrimSpace(name)
	if rateCents < 0 {
		return domain.Provider{}, domain.Invalid("default_rate_cents must not be negative")
	}

	var created domain.Provider
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		color := 0
		if colorIndex != nil {
			if *colorIndex < 0 {
				return domain.Invalid("color_index must not be negative")
			}
			color = *colorIndex % PaletteSize
		} else {
			var err error
			if color, err = nextFreeColor(ctx, tx); err != nil {
				return err
			}
		}

		var position int
		err := tx.QueryRow(ctx, `SELECT COALESCE(MAX(position), -1) + 1 FROM providers`).
			Scan(&position)
		if err != nil {
			return fmt.Errorf("next position: %w", err)
		}

		created, err = scanProvider(tx.QueryRow(ctx, `
			INSERT INTO providers (name, default_rate_cents, color_index, position)
			VALUES ($1, $2, $3, $4)
			RETURNING `+providerCols,
			name, rateCents, color, position))
		return err
	})
	if err != nil {
		return domain.Provider{}, err
	}
	return created, nil
}

func nextFreeColor(ctx context.Context, tx pgx.Tx) (int, error) {
	rows, err := tx.Query(ctx,
		`SELECT DISTINCT color_index FROM providers WHERE archived_at IS NULL`)
	if err != nil {
		return 0, fmt.Errorf("used colors: %w", err)
	}
	defer rows.Close()

	used := map[int]bool{}
	for rows.Next() {
		var c int
		if err := rows.Scan(&c); err != nil {
			return 0, err
		}
		used[c%PaletteSize] = true
	}
	if err := rows.Err(); err != nil {
		return 0, err
	}
	for c := range PaletteSize {
		if !used[c] {
			return c, nil
		}
	}
	// Every colour is taken — wrap around by count.
	return len(used) % PaletteSize, nil
}

// ProviderPatch carries a partial update; nil fields are left untouched.
type ProviderPatch struct {
	Name             *string
	DefaultRateCents *int64
	ColorIndex       *int
	Phone            *string
	RemindWeekdays   *[]int
	RemindAt         *string
}

func (s *Store) UpdateProvider(ctx context.Context, id string, patch ProviderPatch) (domain.Provider, error) {
	if patch.DefaultRateCents != nil && *patch.DefaultRateCents < 0 {
		return domain.Provider{}, domain.Invalid("default_rate_cents must not be negative")
	}
	if patch.ColorIndex != nil && *patch.ColorIndex < 0 {
		return domain.Provider{}, domain.Invalid("color_index must not be negative")
	}
	if patch.Name == nil && patch.DefaultRateCents == nil &&
		patch.ColorIndex == nil && patch.Phone == nil &&
		patch.RemindWeekdays == nil && patch.RemindAt == nil {
		return s.GetProvider(ctx, id)
	}
	if patch.RemindWeekdays != nil {
		for _, d := range *patch.RemindWeekdays {
			if d < 0 || d > 6 {
				return domain.Provider{}, domain.Invalid(
					"dia da semana %d é inválido (0=domingo até 6=sábado)", d)
			}
		}
	}
	if patch.RemindAt != nil {
		if _, err := time.Parse("15:04", *patch.RemindAt); err != nil {
			return domain.Provider{}, domain.Invalid(
				"horário %q deve estar no formato HH:MM", *patch.RemindAt)
		}
	}

	var name *string
	if patch.Name != nil {
		trimmed := strings.TrimSpace(*patch.Name)
		name = &trimmed
	}
	var color *int
	if patch.ColorIndex != nil {
		wrapped := *patch.ColorIndex % PaletteSize
		color = &wrapped
	}
	var phone *string
	if patch.Phone != nil {
		trimmed := strings.TrimSpace(*patch.Phone)
		phone = &trimmed
	}

	// COALESCE keeps this a single statement: a nil parameter means "keep the
	// existing value", which is exactly the PATCH semantics we want.
	return scanProvider(s.pool.QueryRow(ctx, `
		UPDATE providers SET
			name               = COALESCE($2, name),
			default_rate_cents = COALESCE($3, default_rate_cents),
			color_index        = COALESCE($4, color_index),
			phone              = COALESCE($5, phone),
			remind_weekdays    = COALESCE($6, remind_weekdays),
			remind_at          = COALESCE($7::time, remind_at)
		WHERE id = $1 AND archived_at IS NULL
		RETURNING `+providerCols,
		id, name, patch.DefaultRateCents, color, phone,
		patch.RemindWeekdays, patch.RemindAt))
}

// ArchiveProvider soft-deletes a prestadora. Her worked days and payment
// records are history and stay in the database.
func (s *Store) ArchiveProvider(ctx context.Context, id string) error {
	tag, err := s.pool.Exec(ctx,
		`UPDATE providers SET archived_at = now() WHERE id = $1 AND archived_at IS NULL`, id)
	if err != nil {
		return fmt.Errorf("archive provider: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}
	return nil
}

// ListEntries returns every worked day in the half-open range [from, to).
func (s *Store) ListEntries(ctx context.Context, from, to domain.Date) ([]domain.WorkEntry, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT e.id, e.provider_id, e.work_date, e.value_cents, e.kind
		FROM work_entries e
		JOIN providers p ON p.id = e.provider_id AND p.archived_at IS NULL
		WHERE e.work_date >= $1 AND e.work_date < $2
		ORDER BY e.work_date, p.position`,
		from.Time, to.Time)
	if err != nil {
		return nil, fmt.Errorf("list entries: %w", err)
	}
	defer rows.Close()

	entries := make([]domain.WorkEntry, 0, 32)
	for rows.Next() {
		var e domain.WorkEntry
		if err := rows.Scan(&e.ID, &e.ProviderID, &e.Date.Time, &e.ValueCents, &e.Kind); err != nil {
			return nil, fmt.Errorf("scan entry: %w", err)
		}
		entries = append(entries, e)
	}
	return entries, rows.Err()
}

// UpsertEntry records a day. A nil valueCents adopts the value implied by the
// kind — the full rate, half of it, or nothing for an absence — and an existing
// entry has both value and kind replaced.
func (s *Store) UpsertEntry(ctx context.Context, providerID string, date domain.Date, kind domain.EntryKind, valueCents *int64) (domain.WorkEntry, error) {
	if !kind.Valid() {
		return domain.WorkEntry{}, domain.Invalid("kind %q is not valid", kind)
	}
	if valueCents != nil && *valueCents < 0 {
		return domain.WorkEntry{}, domain.Invalid("value_cents must not be negative")
	}
	// An absence costs nothing by definition; the database enforces this too,
	// but rejecting it here gives the caller a usable message instead of a
	// constraint violation.
	if !kind.Billable() && valueCents != nil && *valueCents != 0 {
		return domain.WorkEntry{}, domain.Invalid("uma falta não pode ter valor")
	}

	var e domain.WorkEntry
	err := s.pool.QueryRow(ctx, `
		INSERT INTO work_entries (provider_id, work_date, value_cents, kind)
		SELECT p.id, $2::date,
			COALESCE($3::bigint, CASE $4::text
				WHEN 'half' THEN p.default_rate_cents / 2
				WHEN 'absence' THEN 0
				ELSE p.default_rate_cents
			END),
			$4::text
		FROM providers p
		WHERE p.id = $1 AND p.archived_at IS NULL
		ON CONFLICT (provider_id, work_date)
			DO UPDATE SET value_cents = EXCLUDED.value_cents,
			              kind = EXCLUDED.kind
		RETURNING id, provider_id, work_date, value_cents, kind`,
		providerID, date.Time, valueCents, string(kind),
	).Scan(&e.ID, &e.ProviderID, &e.Date.Time, &e.ValueCents, &e.Kind)

	// No row means the SELECT matched no active prestadora.
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.WorkEntry{}, domain.ErrNotFound
	}
	if err != nil {
		return domain.WorkEntry{}, fmt.Errorf("upsert entry: %w", err)
	}
	return e, nil
}

// DeleteEntry unmarks a day.
func (s *Store) DeleteEntry(ctx context.Context, providerID string, date domain.Date) error {
	tag, err := s.pool.Exec(ctx,
		`DELETE FROM work_entries WHERE provider_id = $1 AND work_date = $2`,
		providerID, date.Time)
	if err != nil {
		return fmt.Errorf("delete entry: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}
	return nil
}

// MonthClosing assembles the Fechamento view for a period: every active
// prestadora with her days, total and payment status.
func (s *Store) MonthClosing(ctx context.Context, period domain.Period) (domain.MonthClosing, error) {
	if err := period.Validate(); err != nil {
		return domain.MonthClosing{}, err
	}
	from, to := period.Bounds()

	providers, err := s.ListProviders(ctx)
	if err != nil {
		return domain.MonthClosing{}, err
	}
	entries, err := s.ListEntries(ctx, from, to)
	if err != nil {
		return domain.MonthClosing{}, err
	}
	payments, err := s.listPayments(ctx, period)
	if err != nil {
		return domain.MonthClosing{}, err
	}

	byProvider := map[string][]domain.ClosingDay{}
	distinctDays := map[string]struct{}{}
	for _, e := range entries {
		byProvider[e.ProviderID] = append(byProvider[e.ProviderID],
			domain.ClosingDay{Date: e.Date, ValueCents: e.ValueCents, Kind: e.Kind})
		// An absence is not a worked day, so it must not inflate the month's
		// "dias trabalhados".
		if e.Kind.Billable() {
			distinctDays[e.Date.String()] = struct{}{}
		}
	}

	result := domain.MonthClosing{
		Year:       period.Year,
		Month:      period.Month,
		Providers:  make([]domain.ProviderClosing, 0, len(providers)),
		WorkedDays: len(distinctDays),
	}

	for _, p := range providers {
		days := byProvider[p.ID]
		if days == nil {
			days = []domain.ClosingDay{}
		}
		var total int64
		var worked, halves, absences int
		for _, d := range days {
			total += d.ValueCents
			switch d.Kind {
			case domain.EntryAbsence:
				absences++
			case domain.EntryHalf:
				worked++
				halves++
			default:
				worked++
			}
		}

		pc := domain.ProviderClosing{
			Provider:     p,
			EntryCount:   worked,
			HalfCount:    halves,
			AbsenceCount: absences,
			TotalCents:   total,
			Days:         days,
		}
		if pay, ok := payments[p.ID]; ok {
			pc.Paid = true
			pc.PaidAt = &pay.at
			pc.PaidAmountCents = &pay.amountCents
		} else {
			result.OutstandingCents += total
		}

		result.TotalCents += total
		result.Providers = append(result.Providers, pc)
	}
	return result, nil
}

type payment struct {
	at          time.Time
	amountCents int64
}

func (s *Store) listPayments(ctx context.Context, period domain.Period) (map[string]payment, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT provider_id, paid_at, paid_amount_cents
		FROM monthly_closings
		WHERE period_year = $1 AND period_month = $2`,
		period.Year, period.Month)
	if err != nil {
		return nil, fmt.Errorf("list payments: %w", err)
	}
	defer rows.Close()

	out := map[string]payment{}
	for rows.Next() {
		var id string
		var p payment
		if err := rows.Scan(&id, &p.at, &p.amountCents); err != nil {
			return nil, fmt.Errorf("scan payment: %w", err)
		}
		out[id] = p
	}
	return out, rows.Err()
}

// MarkPaid records a prestadora's month as paid, snapshotting the amount owed
// at this moment. Computing the sum and writing the record in one transaction
// keeps the snapshot consistent with the days it was derived from.
func (s *Store) MarkPaid(ctx context.Context, period domain.Period, providerID string) error {
	if err := period.Validate(); err != nil {
		return err
	}
	from, to := period.Bounds()

	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var exists bool
		err := tx.QueryRow(ctx,
			`SELECT EXISTS (SELECT 1 FROM providers WHERE id = $1 AND archived_at IS NULL)`,
			providerID).Scan(&exists)
		if err != nil {
			return fmt.Errorf("check provider: %w", err)
		}
		if !exists {
			return domain.ErrNotFound
		}

		var total int64
		var count int
		err = tx.QueryRow(ctx, `
			SELECT COALESCE(SUM(value_cents), 0),
			       COUNT(*) FILTER (WHERE kind <> 'absence')
			FROM work_entries
			WHERE provider_id = $1 AND work_date >= $2 AND work_date < $3`,
			providerID, from.Time, to.Time).Scan(&total, &count)
		if err != nil {
			return fmt.Errorf("sum month: %w", err)
		}
		if count == 0 {
			return domain.Invalid("prestadora has no worked days in %02d/%d", period.Month, period.Year)
		}

		_, err = tx.Exec(ctx, `
			INSERT INTO monthly_closings
				(provider_id, period_year, period_month, paid_amount_cents)
			VALUES ($1, $2, $3, $4)
			ON CONFLICT (provider_id, period_year, period_month)
				DO UPDATE SET paid_amount_cents = EXCLUDED.paid_amount_cents,
				              paid_at = now()`,
			providerID, period.Year, period.Month, total)
		if err != nil {
			return fmt.Errorf("record payment: %w", err)
		}
		return nil
	})
}

// UnmarkPaid reopens a prestadora's month.
func (s *Store) UnmarkPaid(ctx context.Context, period domain.Period, providerID string) error {
	if err := period.Validate(); err != nil {
		return err
	}
	tag, err := s.pool.Exec(ctx, `
		DELETE FROM monthly_closings
		WHERE provider_id = $1 AND period_year = $2 AND period_month = $3`,
		providerID, period.Year, period.Month)
	if err != nil {
		return fmt.Errorf("unmark paid: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}
	return nil
}

// SeedIfEmpty inserts the two prestadoras from the design prototype, but only
// when no prestadora exists at all, so it is safe to leave enabled.
func (s *Store) SeedIfEmpty(ctx context.Context) error {
	var count int
	if err := s.pool.QueryRow(ctx, `SELECT COUNT(*) FROM providers`).Scan(&count); err != nil {
		return fmt.Errorf("count providers: %w", err)
	}
	if count > 0 {
		return nil
	}
	seeds := []struct {
		name  string
		cents int64
	}{
		{"Marina Souza", 18000},
		{"Cleide Ramos", 15000},
	}
	for _, sd := range seeds {
		if _, err := s.CreateProvider(ctx, sd.name, sd.cents, nil); err != nil {
			return fmt.Errorf("seed %s: %w", sd.name, err)
		}
	}
	return nil
}
