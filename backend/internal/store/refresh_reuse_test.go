package store_test

import (
	"context"
	"errors"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/felipearaujo/diarias/backend/internal/db"
	"github.com/felipearaujo/diarias/backend/internal/store"
)

// These exercise SQL, so they need a real Postgres. Point
// DIARIAS_TEST_DATABASE_URL at a throwaway database and they run; otherwise
// they skip.
//
//	DIARIAS_TEST_DATABASE_URL=postgres://... go test ./internal/store/
//
// The database is wiped between tests, so never aim this at real data.
func testPool(t *testing.T) *pgxpool.Pool {
	t.Helper()

	url := os.Getenv("DIARIAS_TEST_DATABASE_URL")
	if url == "" {
		t.Skip("set DIARIAS_TEST_DATABASE_URL to run store integration tests")
	}

	ctx := context.Background()
	pool, err := db.Connect(ctx, url)
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	if err := db.Migrate(ctx, pool); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	// Every table, not just the auth ones: a leftover prestadora or work entry
	// silently changes what a later test's month contains.
	if _, err := pool.Exec(ctx,
		`TRUNCATE sessions, monthly_closings, work_entries, providers, users CASCADE`,
	); err != nil {
		t.Fatalf("reset: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

func newUserWithSession(t *testing.T, st *store.Store) (userID string, session domainSession) {
	t.Helper()
	ctx := context.Background()

	user, err := st.CreateUser(ctx, "felipe", "uma-senha-bem-longa")
	if err != nil {
		t.Fatalf("create user: %v", err)
	}
	s, err := st.CreateSession(ctx, user.ID, "test")
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	return user.ID, domainSession{Token: s.Token, RefreshToken: s.RefreshToken}
}

type domainSession struct{ Token, RefreshToken string }

func TestRefreshRotatesBothTokens(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	_, first := newUserWithSession(t, st)

	rotated, user, err := st.RefreshSession(ctx, first.RefreshToken)
	if err != nil {
		t.Fatalf("refresh: %v", err)
	}
	if user.Username != "felipe" {
		t.Errorf("username = %q", user.Username)
	}
	if rotated.Token == first.Token {
		t.Error("access token was not rotated")
	}
	if rotated.RefreshToken == first.RefreshToken {
		t.Error("refresh token was not rotated")
	}

	// The old access token must stop working immediately.
	if _, err := st.UserForToken(ctx, first.Token); !errors.Is(err, store.ErrInvalidCredentials) {
		t.Errorf("old access token still valid: %v", err)
	}
	if _, err := st.UserForToken(ctx, rotated.Token); err != nil {
		t.Errorf("new access token rejected: %v", err)
	}
}

func TestRefreshTokenIsSingleUse(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	_, first := newUserWithSession(t, st)

	if _, _, err := st.RefreshSession(ctx, first.RefreshToken); err != nil {
		t.Fatalf("first refresh: %v", err)
	}
	_, _, err := st.RefreshSession(ctx, first.RefreshToken)
	if !errors.Is(err, store.ErrInvalidCredentials) {
		t.Fatalf("second use of the same refresh token succeeded: %v", err)
	}
}

func TestReplayedRefreshTokenRevokesEverySession(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	userID, stolen := newUserWithSession(t, st)

	// A second device, to prove the revocation is account-wide.
	other, err := st.CreateSession(ctx, userID, "outro aparelho")
	if err != nil {
		t.Fatalf("second session: %v", err)
	}

	// The thief rotates first.
	thief, _, err := st.RefreshSession(ctx, stolen.RefreshToken)
	if err != nil {
		t.Fatalf("attacker refresh: %v", err)
	}

	// The victim replays the token they both held.
	_, _, err = st.RefreshSession(ctx, stolen.RefreshToken)

	var replay store.ReplayedRefreshTokenError
	if !errors.As(err, &replay) {
		t.Fatalf("replay not detected: %v", err)
	}
	if replay.Username != "felipe" {
		t.Errorf("username = %q", replay.Username)
	}
	// errors.Is must still see it as a rejection, so existing callers work.
	if !errors.Is(err, store.ErrInvalidCredentials) {
		t.Error("replay should also satisfy errors.Is(ErrInvalidCredentials)")
	}

	// This is the point of the whole feature: the thief's rotated session dies
	// too, instead of outliving the victim's re-login.
	if _, err := st.UserForToken(ctx, thief.Token); !errors.Is(err, store.ErrInvalidCredentials) {
		t.Error("the attacker's rotated session survived the replay")
	}
	if _, err := st.UserForToken(ctx, other.Token); !errors.Is(err, store.ErrInvalidCredentials) {
		t.Error("the user's other device was not revoked")
	}
	if _, _, err := st.RefreshSession(ctx, thief.RefreshToken); !errors.Is(err, store.ErrInvalidCredentials) {
		t.Error("the attacker can still refresh")
	}
}

func TestUnknownRefreshTokenDoesNotRevokeAnything(t *testing.T) {
	st := store.New(testPool(t))
	ctx := context.Background()
	_, session := newUserWithSession(t, st)

	// A guess must not be treated as a replay, or anyone could log everyone out.
	_, _, err := st.RefreshSession(ctx, "um-token-que-nunca-existiu")
	if !errors.Is(err, store.ErrInvalidCredentials) {
		t.Fatalf("unexpected error: %v", err)
	}
	var replay store.ReplayedRefreshTokenError
	if errors.As(err, &replay) {
		t.Error("an unknown token was misreported as a replay")
	}
	if _, err := st.UserForToken(ctx, session.Token); err != nil {
		t.Errorf("a wrong guess revoked a live session: %v", err)
	}
}
