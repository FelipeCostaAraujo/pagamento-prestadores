// Command api serves the Diárias HTTP API.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/felipearaujo/diarias/backend/internal/config"
	"github.com/felipearaujo/diarias/backend/internal/db"
	"github.com/felipearaujo/diarias/backend/internal/httpapi"
	"github.com/felipearaujo/diarias/backend/internal/push"
	"github.com/felipearaujo/diarias/backend/internal/reminders"
	"github.com/felipearaujo/diarias/backend/internal/store"

	// Embeds the timezone database so the Alpine image does not need tzdata
	// installed. Reminder times are meaningless without it.
	_ "time/tzdata"
)

func main() {
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	})))

	// `api user ...` manages accounts against the same database and config as
	// the server, so the deployed image needs no extra tooling. Anything else
	// starts the HTTP server.
	if len(os.Args) > 1 && os.Args[1] == "user" {
		if err := runUserCommand(os.Args[2:]); err != nil {
			fmt.Fprintln(os.Stderr, "erro:", err)
			os.Exit(1)
		}
		return
	}

	if err := run(); err != nil {
		slog.Error("fatal", "error", err)
		os.Exit(1)
	}
}

func run() error {
	// Interrupt cancels startup as well as the running server, so a Ctrl-C
	// while waiting for Postgres exits promptly.
	ctx, stop := signal.NotifyContext(context.Background(),
		os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg, err := config.Load(".env", "../.env")
	if err != nil {
		return err
	}

	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()

	if err := db.Migrate(ctx, pool); err != nil {
		return err
	}

	st := store.New(pool)
	if cfg.Seed {
		if err := st.SeedIfEmpty(ctx); err != nil {
			return err
		}
	}

	// A published API with no accounts refuses everything, which looks like a
	// bug from the app. Say so at boot instead of leaving it to be discovered.
	if n, err := st.CountUsers(ctx); err != nil {
		return err
	} else if n == 0 {
		slog.Warn("no user accounts exist — every request will be rejected; " +
			"create one with: api user add <usuário>")
	}

	go sweepSessions(ctx, st)
	startReminders(ctx, st, cfg)

	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           httpapi.NewHandler(st, cfg),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	errc := make(chan error, 1)
	go func() {
		slog.Info("listening", "addr", cfg.Addr,
			"seed", cfg.Seed, "trust_proxy", cfg.TrustProxy)
		if err := srv.ListenAndServe(); err != nil &&
			!errors.Is(err, http.ErrServerClosed) {
			errc <- err
		}
	}()

	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
		slog.Info("shutting down")
	}

	// Give in-flight requests a bounded window to finish.
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return srv.Shutdown(shutdownCtx)
}

// startReminders brings up the push scheduler, or explains why it stays off.
//
// Reminders are a convenience: a missing or broken credential must never stop
// the API from serving, so every failure here is logged and swallowed.
func startReminders(ctx context.Context, st *store.Store, cfg config.Config) {
	location, err := time.LoadLocation(cfg.Timezone)
	if err != nil {
		slog.Error("reminders disabled: unknown timezone",
			"timezone", cfg.Timezone, "error", err)
		return
	}

	sender, err := push.New(ctx, cfg.FCMCredentials)
	if errors.Is(err, push.ErrDisabled) {
		slog.Warn("reminders disabled: set DIARIAS_FCM_CREDENTIALS to the " +
			"service-account JSON to enable push")
		return
	}
	if err != nil {
		slog.Error("reminders disabled: cannot use the service account",
			"path", cfg.FCMCredentials, "error", err)
		return
	}

	slog.Info("push enabled", "firebase_project", sender.ProjectID())
	go reminders.New(st, sender, location, cfg.PaymentReminderDay).Run(ctx)
}

// sweepSessions removes expired rows periodically.
//
// Expiry is enforced in the query that authenticates, so this is housekeeping
// rather than a security control — it just stops the table growing forever.
func sweepSessions(ctx context.Context, st *store.Store) {
	ticker := time.NewTicker(6 * time.Hour)
	defer ticker.Stop()

	for {
		removed, err := st.DeleteExpiredSessions(ctx)
		if err != nil && ctx.Err() == nil {
			slog.Error("sweep sessions", "error", err)
		} else if removed > 0 {
			slog.Info("expired sessions removed", "count", removed)
		}

		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}
