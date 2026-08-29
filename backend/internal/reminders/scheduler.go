// Package reminders decides which push notifications are due and sends them.
package reminders

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/felipearaujo/diarias/backend/internal/domain"
	"github.com/felipearaujo/diarias/backend/internal/push"
	"github.com/felipearaujo/diarias/backend/internal/store"
)

// tick is how often the scheduler looks for work.
//
// Five minutes is well inside "close enough" for a reminder pinned to an hour,
// and keeps the query load negligible. It also bounds how late a reminder can
// be after a restart.
const tick = 5 * time.Minute

// Scheduler sends the household's reminders.
type Scheduler struct {
	store  *store.Store
	sender *push.Sender
	// Where "19:00" and "the 5th" are interpreted. Reminders are about someone's
	// day, so they must follow the household's clock, not the server's.
	location *time.Location
	// Day of month for the payment nudge.
	paymentDay int
}

func New(st *store.Store, sender *push.Sender, loc *time.Location, paymentDay int) *Scheduler {
	return &Scheduler{
		store:      st,
		sender:     sender,
		location:   loc,
		paymentDay: paymentDay,
	}
}

// Run checks for due reminders until ctx is cancelled.
func (s *Scheduler) Run(ctx context.Context) {
	ticker := time.NewTicker(tick)
	defer ticker.Stop()

	slog.Info("reminder scheduler started",
		"timezone", s.location.String(),
		"payment_day", s.paymentDay,
		"every", tick.String())

	for {
		s.runOnce(ctx)
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func (s *Scheduler) runOnce(ctx context.Context) {
	now := time.Now().In(s.location)

	if err := s.sendWorkReminders(ctx, now); err != nil && ctx.Err() == nil {
		slog.Error("work reminders", "error", err)
	}
	if err := s.sendPaymentReminder(ctx, now); err != nil && ctx.Err() == nil {
		slog.Error("payment reminder", "error", err)
	}
}

// sendWorkReminders asks about people who were expected today and whose day
// nobody has recorded.
func (s *Scheduler) sendWorkReminders(ctx context.Context, now time.Time) error {
	due, err := s.store.DueWorkReminders(ctx, now)
	if err != nil {
		return err
	}
	if len(due) == 0 {
		return nil
	}

	today := domain.NewDate(now.Year(), now.Month(), now.Day())
	for _, p := range due {
		// Claim before sending: a duplicate push is worse than a reminder that
		// is missed once because the process died between the two.
		claimed, err := s.store.MarkReminderSent(ctx, store.ReminderWork, &p.ID, today)
		if err != nil {
			return err
		}
		if !claimed {
			continue
		}

		name := p.Name
		if strings.TrimSpace(name) == "" {
			name = "a prestadora"
		}
		err = s.deliver(ctx, push.Message{
			Title: "Anotar a diária",
			Body: fmt.Sprintf(
				"%s trabalhou hoje? Toque para marcar o dia.", name),
			Data: map[string]string{
				"kind":        store.ReminderWork,
				"provider_id": p.ID,
				"date":        today.String(),
			},
		})
		if err != nil {
			// Let the next tick try again rather than losing the reminder.
			s.store.ReleaseReminder(ctx, store.ReminderWork, &p.ID, today)
			return err
		}
		slog.Info("work reminder sent", "provider", name, "date", today.String())
	}
	return nil
}

// sendPaymentReminder nudges on payday when last month is still open.
func (s *Scheduler) sendPaymentReminder(ctx context.Context, now time.Time) error {
	if now.Day() != s.paymentDay {
		return nil
	}

	names, owed, err := s.store.UnpaidPrevious(ctx, now)
	if err != nil {
		return err
	}
	if len(names) == 0 {
		return nil
	}

	today := domain.NewDate(now.Year(), now.Month(), now.Day())
	claimed, err := s.store.MarkReminderSent(ctx, store.ReminderPayment, nil, today)
	if err != nil || !claimed {
		return err
	}

	body := fmt.Sprintf("%s a pagar do mês passado: %s.",
		formatMoney(owed), humanList(names))
	if err := s.deliver(ctx, push.Message{
		Title: "Fechamento em aberto",
		Body:  body,
		Data:  map[string]string{"kind": store.ReminderPayment},
	}); err != nil {
		s.store.ReleaseReminder(ctx, store.ReminderPayment, nil, today)
		return err
	}
	slog.Info("payment reminder sent", "owed_cents", owed, "people", len(names))
	return nil
}

// deliver sends to every registered device and forgets the ones FCM rejects.
func (s *Scheduler) deliver(ctx context.Context, msg push.Message) error {
	devices, err := s.store.AllDeviceTargets(ctx)
	if err != nil {
		return err
	}
	if len(devices) == 0 {
		// Nobody has the app installed with push allowed. Not an error, but
		// worth saying — otherwise a silent phone looks like a broken feature.
		slog.Warn("reminder due but no device is registered", "title", msg.Title)
		return nil
	}

	targets := make([]push.Target, 0, len(devices))
	for _, device := range devices {
		targets = append(targets, push.Target{
			Identifier: device.Identifier,
			FID:        strings.HasSuffix(device.Platform, "-fid"),
		})
	}

	stale, err := s.sender.Send(ctx, targets, msg)
	for _, identifier := range stale {
		if rmErr := s.store.UnregisterDevice(ctx, identifier); rmErr != nil {
			slog.Error("drop stale token", "error", rmErr)
		}
	}
	return err
}

// formatMoney renders cents in Brazilian style, matching the app.
func formatMoney(cents int64) string {
	sign := ""
	if cents < 0 {
		sign = "-"
		cents = -cents
	}
	reais := cents / 100
	var grouped []string
	digits := fmt.Sprintf("%d", reais)
	for len(digits) > 3 {
		grouped = append([]string{digits[len(digits)-3:]}, grouped...)
		digits = digits[:len(digits)-3]
	}
	grouped = append([]string{digits}, grouped...)
	return fmt.Sprintf("R$ %s%s,%02d", sign, strings.Join(grouped, "."), cents%100)
}

// humanList joins names the way a person would say them.
func humanList(names []string) string {
	switch len(names) {
	case 0:
		return ""
	case 1:
		return names[0]
	default:
		return strings.Join(names[:len(names)-1], ", ") + " e " + names[len(names)-1]
	}
}
