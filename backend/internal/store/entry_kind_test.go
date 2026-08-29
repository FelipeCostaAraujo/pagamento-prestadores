package store_test

import (
	"context"
	"testing"

	"github.com/felipearaujo/diarias/backend/internal/domain"
	"github.com/felipearaujo/diarias/backend/internal/store"
)

// Same guard as the other store tests: needs DIARIAS_TEST_DATABASE_URL.
func newProvider(t *testing.T, st *store.Store, rateCents int64) domain.Provider {
	t.Helper()
	p, err := st.CreateProvider(context.Background(), "Marília", rateCents, nil)
	if err != nil {
		t.Fatalf("create provider: %v", err)
	}
	return p
}

func TestEntryKindDrivesTheDefaultValue(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	p := newProvider(t, st, 17000)

	cases := []struct {
		kind domain.EntryKind
		want int64
	}{
		{domain.EntryFull, 17000},
		{domain.EntryHalf, 8500},
		{domain.EntryAbsence, 0},
	}
	for i, tc := range cases {
		date := domain.NewDate(2026, 8, i+1)
		entry, err := st.UpsertEntry(ctx, p.ID, date, tc.kind, nil)
		if err != nil {
			t.Fatalf("upsert %s: %v", tc.kind, err)
		}
		if entry.ValueCents != tc.want {
			t.Errorf("%s value = %d, want %d", tc.kind, entry.ValueCents, tc.want)
		}
		if entry.Kind != tc.kind {
			t.Errorf("kind = %q, want %q", entry.Kind, tc.kind)
		}
	}
}

func TestAbsenceCannotCarryAValue(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	p := newProvider(t, st, 17000)

	value := int64(17000)
	_, err := st.UpsertEntry(ctx, p.ID,
		domain.NewDate(2026, 8, 4), domain.EntryAbsence, &value)
	if err == nil {
		t.Fatal("an absence with a value was accepted")
	}
}

func TestChangingAKindReplacesTheValue(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	p := newProvider(t, st, 17000)
	date := domain.NewDate(2026, 8, 5)

	if _, err := st.UpsertEntry(ctx, p.ID, date, domain.EntryFull, nil); err != nil {
		t.Fatalf("full: %v", err)
	}
	// She ended up only working the morning.
	entry, err := st.UpsertEntry(ctx, p.ID, date, domain.EntryHalf, nil)
	if err != nil {
		t.Fatalf("half: %v", err)
	}
	if entry.ValueCents != 8500 {
		t.Errorf("value = %d, want 8500", entry.ValueCents)
	}
}

func TestClosingSeparatesWorkedDaysFromAbsences(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	p := newProvider(t, st, 17000)

	for _, e := range []struct {
		day  int
		kind domain.EntryKind
	}{
		{3, domain.EntryFull},
		{4, domain.EntryHalf},
		{5, domain.EntryAbsence},
	} {
		if _, err := st.UpsertEntry(ctx, p.ID,
			domain.NewDate(2026, 8, e.day), e.kind, nil); err != nil {
			t.Fatalf("upsert day %d: %v", e.day, err)
		}
	}

	closing, err := st.MonthClosing(ctx, domain.Period{Year: 2026, Month: 8})
	if err != nil {
		t.Fatalf("closing: %v", err)
	}
	pc := closing.Providers[0]

	// The absence is on the calendar but is not a diária and is not owed.
	if pc.EntryCount != 2 {
		t.Errorf("entry_count = %d, want 2 (full + half)", pc.EntryCount)
	}
	if pc.HalfCount != 1 {
		t.Errorf("half_count = %d, want 1", pc.HalfCount)
	}
	if pc.AbsenceCount != 1 {
		t.Errorf("absence_count = %d, want 1", pc.AbsenceCount)
	}
	if pc.TotalCents != 25500 {
		t.Errorf("total = %d, want 25500 (170,00 + 85,00)", pc.TotalCents)
	}
	if len(pc.Days) != 3 {
		t.Errorf("days = %d, want 3 — the absence still shows", len(pc.Days))
	}
	if closing.WorkedDays != 2 {
		t.Errorf("worked_days = %d, want 2", closing.WorkedDays)
	}
}

func TestAMonthOfOnlyAbsencesCannotBeMarkedPaid(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	p := newProvider(t, st, 17000)

	if _, err := st.UpsertEntry(ctx, p.ID,
		domain.NewDate(2026, 8, 6), domain.EntryAbsence, nil); err != nil {
		t.Fatalf("upsert: %v", err)
	}

	// There is a row for the month, but nothing was worked and nothing is owed.
	err := st.MarkPaid(ctx, domain.Period{Year: 2026, Month: 8}, p.ID)
	if err == nil {
		t.Fatal("a month with only absences was marked as paid")
	}
}
