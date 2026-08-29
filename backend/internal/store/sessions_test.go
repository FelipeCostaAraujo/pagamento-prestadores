package store_test

import (
	"context"
	"errors"
	"testing"

	"github.com/felipearaujo/diarias/backend/internal/domain"
	"github.com/felipearaujo/diarias/backend/internal/store"
)

func TestListSessionsFlagsTheCallersOwnDevice(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	userID, mine := newUserWithSession(t, st)

	other, err := st.CreateSession(ctx, userID, "Diárias Android")
	if err != nil {
		t.Fatalf("second session: %v", err)
	}

	list, err := st.ListSessions(ctx, userID, mine.Token)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(list) != 2 {
		t.Fatalf("got %d sessions, want 2", len(list))
	}

	var current, ids int
	for _, s := range list {
		if s.Current {
			current++
		}
		if s.ID != "" {
			ids++
		}
	}
	if current != 1 {
		t.Errorf("%d sessions flagged as current, want exactly 1", current)
	}
	if ids != 2 {
		t.Error("every session needs a public id to be revocable")
	}
	_ = other
}

func TestRevokeOtherSessionsKeepsTheCaller(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	userID, mine := newUserWithSession(t, st)

	for range 2 {
		if _, err := st.CreateSession(ctx, userID, "outro"); err != nil {
			t.Fatalf("session: %v", err)
		}
	}

	revoked, err := st.DeleteOtherSessions(ctx, userID, mine.Token)
	if err != nil {
		t.Fatalf("revoke others: %v", err)
	}
	if revoked != 2 {
		t.Errorf("revoked %d, want 2", revoked)
	}
	// The device that pressed the button must stay signed in.
	if _, err := st.UserForToken(ctx, mine.Token); err != nil {
		t.Errorf("the caller was signed out by its own request: %v", err)
	}
}

func TestRevokeSessionIsScopedToItsOwner(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	victimID, victim := newUserWithSession(t, st)

	attacker, err := st.CreateUser(ctx, "outro", "uma-senha-bem-longa")
	if err != nil {
		t.Fatalf("create user: %v", err)
	}

	list, err := st.ListSessions(ctx, victimID, victim.Token)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	victimSessionID := list[0].ID

	// Knowing another account's session id must not be enough to revoke it.
	err = st.DeleteSessionByID(ctx, attacker.ID, victimSessionID)
	if !errors.Is(err, domain.ErrNotFound) {
		t.Fatalf("cross-account revoke returned %v, want ErrNotFound", err)
	}
	if _, err := st.UserForToken(ctx, victim.Token); err != nil {
		t.Error("another user managed to sign this session out")
	}
}
