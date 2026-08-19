package httpapi

import (
	"log/slog"
	"net/http"
	"slices"
	"strings"
	"time"
)

// cors answers preflight requests and echoes an allowed origin. It sits
// outside the session check so a browser preflight — which carries no
// Authorization header — is never rejected as unauthorized.
func cors(origins []string, next http.Handler) http.Handler {
	allowAny := slices.Contains(origins, "*")

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		switch {
		case origin == "":
			// Not a browser request; nothing to negotiate.
		case allowAny:
			w.Header().Set("Access-Control-Allow-Origin", "*")
		case slices.Contains(origins, origin):
			w.Header().Set("Access-Control-Allow-Origin", origin)
			// The response varies by request origin, so caches must not reuse
			// one origin's response for another.
			w.Header().Add("Vary", "Origin")
		}

		if r.Method == http.MethodOptions {
			w.Header().Set("Access-Control-Allow-Methods",
				"GET, POST, PUT, PATCH, DELETE, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers",
				"Content-Type, Authorization")
			w.Header().Set("Access-Control-Max-Age", "600")
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// statusRecorder captures the status code so logging can report it.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

func logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)

		// Query strings carry provider ids and dates but no secrets; keeping
		// them makes the log useful for debugging the app.
		path := r.URL.Path
		if r.URL.RawQuery != "" {
			path += "?" + r.URL.RawQuery
		}
		level := slog.LevelInfo
		if rec.status >= 500 {
			level = slog.LevelError
		}
		slog.Log(r.Context(), level, "http",
			"method", r.Method,
			"path", path,
			"status", rec.status,
			"duration", time.Since(start).Round(time.Microsecond).String(),
		)
	})
}

// trimTrailingSlash is used by the server so /api/v1/providers/ and
// /api/v1/providers reach the same handler.
func trimTrailingSlash(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if p := r.URL.Path; len(p) > 1 && strings.HasSuffix(p, "/") {
			r.URL.Path = strings.TrimRight(p, "/")
		}
		next.ServeHTTP(w, r)
	})
}
