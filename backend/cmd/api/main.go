// Command api serves the Diárias HTTP API.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/felipearaujo/diarias/backend/internal/config"
	"github.com/felipearaujo/diarias/backend/internal/db"
	"github.com/felipearaujo/diarias/backend/internal/httpapi"
	"github.com/felipearaujo/diarias/backend/internal/store"
)

func main() {
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	})))

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
			"auth", cfg.APIToken != "", "seed", cfg.Seed)
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
