package store_test

import (
	"context"
	"testing"
	"time"

	"github.com/felipearaujo/diarias/backend/internal/domain"
	"github.com/felipearaujo/diarias/backend/internal/store"
)

// 2026-08-03 is a Monday; 2026-08-04 a Tuesday.
var monday = time.Date(2026, 8, 3, 19, 30, 0, 0, time.UTC)

func scheduled(t *testing.T, st *store.Store, weekdays []int, at string) domain.Provider {
	t.Helper()
	ctx := context.Background()
	p, err := st.CreateProvider(ctx, "Marília", 17000, nil)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	updated, err := st.UpdateProvider(ctx, p.ID, store.ProviderPatch{
		RemindWeekdays: &weekdays,
		RemindAt:       &at,
	})
	if err != nil {
		t.Fatalf("schedule: %v", err)
	}
	return updated
}

func TestWorkReminderFiresOnAScheduledDayAfterItsTime(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	scheduled(t, st, []int{1, 5}, "19:00") // segunda e sexta

	due, err := st.DueWorkReminders(ctx, monday)
	if err != nil {
		t.Fatalf("due: %v", err)
	}
	if len(due) != 1 {
		t.Fatalf("got %d due, want 1", len(due))
	}
	if due[0].RemindAt != "19:00" {
		t.Errorf("remind_at = %q", due[0].RemindAt)
	}
}

func TestWorkReminderStaysQuietBeforeItsTime(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	scheduled(t, st, []int{1}, "19:00")

	// 18:30 — ela ainda está saindo.
	early := time.Date(2026, 8, 3, 18, 30, 0, 0, time.UTC)
	due, err := st.DueWorkReminders(ctx, early)
	if err != nil {
		t.Fatalf("due: %v", err)
	}
	if len(due) != 0 {
		t.Errorf("reminded %d before the hour, want 0", len(due))
	}
}

func TestWorkReminderIgnoresDaysNotScheduled(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	scheduled(t, st, []int{1, 5}, "19:00")

	tuesday := time.Date(2026, 8, 4, 19, 30, 0, 0, time.UTC)
	due, err := st.DueWorkReminders(ctx, tuesday)
	if err != nil {
		t.Fatalf("due: %v", err)
	}
	if len(due) != 0 {
		t.Errorf("reminded on an unscheduled day")
	}
}

func TestWorkReminderStopsOnceTheDayIsRecorded(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	p := scheduled(t, st, []int{1}, "19:00")

	// Marcar como falta também conta: alguém já decidiu sobre o dia.
	if _, err := st.UpsertEntry(ctx, p.ID,
		domain.NewDate(2026, 8, 3), domain.EntryAbsence, nil); err != nil {
		t.Fatalf("upsert: %v", err)
	}

	due, err := st.DueWorkReminders(ctx, monday)
	if err != nil {
		t.Fatalf("due: %v", err)
	}
	if len(due) != 0 {
		t.Errorf("nagged about a day that was already decided")
	}
}

func TestSomeoneWithoutAScheduleIsNeverReminded(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	// Cristiane só vem quando chamada.
	if _, err := st.CreateProvider(ctx, "Cristiane", 20000, nil); err != nil {
		t.Fatalf("create: %v", err)
	}

	for _, day := range []int{3, 4, 5, 6, 7} {
		when := time.Date(2026, 8, day, 23, 0, 0, 0, time.UTC)
		due, err := st.DueWorkReminders(ctx, when)
		if err != nil {
			t.Fatalf("due: %v", err)
		}
		if len(due) != 0 {
			t.Fatalf("reminded about someone with no routine, on day %d", day)
		}
	}
}

func TestAReminderIsClaimedOnlyOnce(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	p := scheduled(t, st, []int{1}, "19:00")
	today := domain.NewDate(2026, 8, 3)

	first, err := st.MarkReminderSent(ctx, store.ReminderWork, &p.ID, today)
	if err != nil || !first {
		t.Fatalf("first claim failed: %v %v", first, err)
	}
	// A second scheduler tick, or a restart, must not send again.
	second, err := st.MarkReminderSent(ctx, store.ReminderWork, &p.ID, today)
	if err != nil {
		t.Fatalf("second claim: %v", err)
	}
	if second {
		t.Error("the same reminder was claimed twice")
	}

	due, err := st.DueWorkReminders(ctx, monday)
	if err != nil {
		t.Fatalf("due: %v", err)
	}
	if len(due) != 0 {
		t.Error("an already-sent reminder came back as due")
	}
}

func TestAReleasedReminderIsTriedAgain(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	p := scheduled(t, st, []int{1}, "19:00")
	today := domain.NewDate(2026, 8, 3)

	if _, err := st.MarkReminderSent(ctx, store.ReminderWork, &p.ID, today); err != nil {
		t.Fatalf("claim: %v", err)
	}
	// The send failed, so the claim is given back.
	st.ReleaseReminder(ctx, store.ReminderWork, &p.ID, today)

	due, err := st.DueWorkReminders(ctx, monday)
	if err != nil {
		t.Fatalf("due: %v", err)
	}
	if len(due) != 1 {
		t.Error("a failed send was never retried")
	}
}

func TestUnpaidPreviousReportsOnlyWhatIsOwed(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	marilia := scheduled(t, st, []int{1}, "19:00")
	cristiane, err := st.CreateProvider(ctx, "Cristiane", 20000, nil)
	if err != nil {
		t.Fatalf("create: %v", err)
	}

	// Agosto: as duas trabalharam.
	for _, id := range []string{marilia.ID, cristiane.ID} {
		if _, err := st.UpsertEntry(ctx, id,
			domain.NewDate(2026, 8, 10), domain.EntryFull, nil); err != nil {
			t.Fatalf("upsert: %v", err)
		}
	}
	// A Cristiane já foi paga.
	if err := st.MarkPaid(ctx, domain.Period{Year: 2026, Month: 8}, cristiane.ID); err != nil {
		t.Fatalf("mark paid: %v", err)
	}

	// Dia 5 de setembro, o pagamento do mês anterior.
	payday := time.Date(2026, 9, 5, 9, 0, 0, 0, time.UTC)
	names, owed, err := st.UnpaidPrevious(ctx, payday)
	if err != nil {
		t.Fatalf("unpaid: %v", err)
	}
	if len(names) != 1 || names[0] != "Marília" {
		t.Errorf("names = %v, want only Marília", names)
	}
	if owed != 17000 {
		t.Errorf("owed = %d, want 17000 — a Cristiane já foi paga", owed)
	}
}

func TestPaymentReminderIsSilentWhenEverythingIsSettled(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	p := scheduled(t, st, []int{1}, "19:00")

	if _, err := st.UpsertEntry(ctx, p.ID,
		domain.NewDate(2026, 8, 10), domain.EntryFull, nil); err != nil {
		t.Fatalf("upsert: %v", err)
	}
	if err := st.MarkPaid(ctx, domain.Period{Year: 2026, Month: 8}, p.ID); err != nil {
		t.Fatalf("mark paid: %v", err)
	}

	payday := time.Date(2026, 9, 5, 9, 0, 0, 0, time.UTC)
	names, owed, err := st.UnpaidPrevious(ctx, payday)
	if err != nil {
		t.Fatalf("unpaid: %v", err)
	}
	if len(names) != 0 || owed != 0 {
		t.Errorf("nudged about a month that is fully paid: %v %d", names, owed)
	}
}

func TestJanuaryLooksBackAtDecember(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	p := scheduled(t, st, []int{1}, "19:00")

	if _, err := st.UpsertEntry(ctx, p.ID,
		domain.NewDate(2026, 12, 15), domain.EntryFull, nil); err != nil {
		t.Fatalf("upsert: %v", err)
	}

	// 5 de janeiro de 2027 deve olhar para dezembro de 2026, não mês 0.
	payday := time.Date(2027, 1, 5, 9, 0, 0, 0, time.UTC)
	names, owed, err := st.UnpaidPrevious(ctx, payday)
	if err != nil {
		t.Fatalf("unpaid: %v", err)
	}
	if len(names) != 1 || owed != 17000 {
		t.Errorf("year rollover missed December: %v %d", names, owed)
	}
}

func TestRegisteringADeviceMovesItBetweenAccounts(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()

	first, err := st.CreateUser(ctx, "faraujo", "uma-senha-bem-longa")
	if err != nil {
		t.Fatalf("create user: %v", err)
	}
	second, err := st.CreateUser(ctx, "rberlamina", "outra-senha-bem-longa")
	if err != nil {
		t.Fatalf("create user: %v", err)
	}

	if err := st.RegisterDevice(ctx, first.ID, "token-abc", "android"); err != nil {
		t.Fatalf("register: %v", err)
	}
	// The same phone, now signed in as someone else. FCM hands back the same
	// token, so it must not stay attached to the previous account.
	if err := st.RegisterDevice(ctx, second.ID, "token-abc", "android"); err != nil {
		t.Fatalf("re-register: %v", err)
	}

	targets, err := st.AllDeviceTargets(ctx)
	if err != nil {
		t.Fatalf("targets: %v", err)
	}
	if len(targets) != 1 {
		t.Errorf("got %d targets, want 1 — the device was duplicated", len(targets))
	}
	if len(targets) == 1 && targets[0].Platform != "android" {
		t.Errorf("platform = %q, want android", targets[0].Platform)
	}
}
