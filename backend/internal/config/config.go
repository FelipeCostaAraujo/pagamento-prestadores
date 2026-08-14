// Package config loads runtime configuration from the environment, with an
// optional .env file for local development.
package config

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	DatabaseURL string
	Addr        string
	// APIToken, when non-empty, is required as `Authorization: Bearer <token>`
	// on every /api request.
	APIToken    string
	CORSOrigins []string
	Seed        bool
}

// Load reads configuration from the environment. If a readable file exists at
// any of envFiles, its values are loaded first but never override variables
// already present in the real environment.
func Load(envFiles ...string) (Config, error) {
	for _, f := range envFiles {
		if err := loadEnvFile(f); err != nil {
			return Config{}, fmt.Errorf("load %s: %w", f, err)
		}
	}

	cfg := Config{
		DatabaseURL: env("DIARIAS_DATABASE_URL", ""),
		Addr:        env("DIARIAS_ADDR", ":8080"),
		APIToken:    env("DIARIAS_API_TOKEN", ""),
		Seed:        env("DIARIAS_SEED", "false") == "true",
	}

	for _, o := range strings.Split(env("DIARIAS_CORS_ORIGINS", "*"), ",") {
		if o = strings.TrimSpace(o); o != "" {
			cfg.CORSOrigins = append(cfg.CORSOrigins, o)
		}
	}

	if cfg.DatabaseURL == "" {
		return Config{}, fmt.Errorf("DIARIAS_DATABASE_URL is required")
	}
	return cfg, nil
}

func env(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}

// loadEnvFile parses a minimal KEY=VALUE file. A missing file is not an error —
// the environment alone is a valid way to configure the service.
func loadEnvFile(path string) error {
	f, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		key = strings.TrimSpace(key)
		value = strings.TrimSpace(value)
		// Strip surrounding quotes, tolerating values that contain '='.
		if unquoted, err := strconv.Unquote(value); err == nil {
			value = unquoted
		}
		if _, exists := os.LookupEnv(key); !exists {
			if err := os.Setenv(key, value); err != nil {
				return err
			}
		}
	}
	return sc.Err()
}
