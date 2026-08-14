// Package httpapi exposes the Diárias store over JSON/HTTP.
package httpapi

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"

	"github.com/felipearaujo/diarias/backend/internal/config"
	"github.com/felipearaujo/diarias/backend/internal/domain"
	"github.com/felipearaujo/diarias/backend/internal/store"
)

type Server struct {
	store *store.Store
	cfg   config.Config
}

// NewHandler builds the fully-wrapped HTTP handler for the API.
func NewHandler(st *store.Store, cfg config.Config) http.Handler {
	s := &Server{store: st, cfg: cfg}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/health", s.health)

	mux.HandleFunc("GET /api/v1/providers", s.listProviders)
	mux.HandleFunc("POST /api/v1/providers", s.createProvider)
	mux.HandleFunc("PATCH /api/v1/providers/{id}", s.updateProvider)
	mux.HandleFunc("DELETE /api/v1/providers/{id}", s.deleteProvider)

	mux.HandleFunc("GET /api/v1/entries", s.listEntries)
	mux.HandleFunc("PUT /api/v1/entries", s.upsertEntry)
	mux.HandleFunc("DELETE /api/v1/entries", s.deleteEntry)

	mux.HandleFunc("GET /api/v1/months/{year}/{month}", s.monthClosing)
	mux.HandleFunc("PUT /api/v1/months/{year}/{month}/providers/{providerID}/payment", s.markPaid)
	mux.HandleFunc("DELETE /api/v1/months/{year}/{month}/providers/{providerID}/payment", s.unmarkPaid)

	// Outermost first: log everything, normalise the path, answer CORS
	// preflight before auth can reject it, then require the token.
	return logging(trimTrailingSlash(
		cors(cfg.CORSOrigins, requireToken(cfg.APIToken, mux))))
}

// ---------------------------------------------------------------- providers --

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) listProviders(w http.ResponseWriter, r *http.Request) {
	providers, err := s.store.ListProviders(r.Context())
	if err != nil {
		writeError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, providers)
}

type providerBody struct {
	Name             *string `json:"name"`
	DefaultRateCents *int64  `json:"default_rate_cents"`
	ColorIndex       *int    `json:"color_index"`
}

func (s *Server) createProvider(w http.ResponseWriter, r *http.Request) {
	body, err := decode[providerBody](r)
	if err != nil {
		writeError(w, r, err)
		return
	}

	name := ""
	if body.Name != nil {
		name = *body.Name
	}
	// A new prestadora may legitimately start unnamed — the design's
	// "+ Nova prestadora" adds an empty card the user then types into.
	var rate int64
	if body.DefaultRateCents != nil {
		rate = *body.DefaultRateCents
	}

	created, err := s.store.CreateProvider(r.Context(), name, rate, body.ColorIndex)
	if err != nil {
		writeError(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, created)
}

func (s *Server) updateProvider(w http.ResponseWriter, r *http.Request) {
	body, err := decode[providerBody](r)
	if err != nil {
		writeError(w, r, err)
		return
	}
	updated, err := s.store.UpdateProvider(r.Context(), r.PathValue("id"), store.ProviderPatch{
		Name:             body.Name,
		DefaultRateCents: body.DefaultRateCents,
		ColorIndex:       body.ColorIndex,
	})
	if err != nil {
		writeError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, updated)
}

func (s *Server) deleteProvider(w http.ResponseWriter, r *http.Request) {
	if err := s.store.ArchiveProvider(r.Context(), r.PathValue("id")); err != nil {
		writeError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ------------------------------------------------------------------ entries --

// listEntries accepts either ?year=&month= or an explicit ?from=&to= range.
// The range is half-open: from is included, to is not.
func (s *Server) listEntries(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()

	var from, to domain.Date
	switch {
	case q.Get("year") != "" || q.Get("month") != "":
		period, err := parsePeriod(q.Get("year"), q.Get("month"))
		if err != nil {
			writeError(w, r, err)
			return
		}
		from, to = period.Bounds()
	case q.Get("from") != "" && q.Get("to") != "":
		var err error
		if from, err = domain.ParseDate(q.Get("from")); err != nil {
			writeError(w, r, err)
			return
		}
		if to, err = domain.ParseDate(q.Get("to")); err != nil {
			writeError(w, r, err)
			return
		}
		if to.Before(from.Time) {
			writeError(w, r, domain.Invalid("to must not be before from"))
			return
		}
	default:
		writeError(w, r, domain.Invalid("provide year and month, or from and to"))
		return
	}

	entries, err := s.store.ListEntries(r.Context(), from, to)
	if err != nil {
		writeError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, entries)
}

type entryBody struct {
	ProviderID string       `json:"provider_id"`
	Date       *domain.Date `json:"date"`
	// Omit to adopt the prestadora's current default rate.
	ValueCents *int64 `json:"value_cents"`
}

func (s *Server) upsertEntry(w http.ResponseWriter, r *http.Request) {
	body, err := decode[entryBody](r)
	if err != nil {
		writeError(w, r, err)
		return
	}
	if body.ProviderID == "" {
		writeError(w, r, domain.Invalid("provider_id is required"))
		return
	}
	if body.Date == nil {
		writeError(w, r, domain.Invalid("date is required"))
		return
	}

	entry, err := s.store.UpsertEntry(r.Context(), body.ProviderID, *body.Date, body.ValueCents)
	if err != nil {
		writeError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, entry)
}

func (s *Server) deleteEntry(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	providerID := q.Get("provider_id")
	if providerID == "" {
		writeError(w, r, domain.Invalid("provider_id is required"))
		return
	}
	date, err := domain.ParseDate(q.Get("date"))
	if err != nil {
		writeError(w, r, err)
		return
	}
	if err := s.store.DeleteEntry(r.Context(), providerID, date); err != nil {
		writeError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ----------------------------------------------------------------- closings --

func (s *Server) monthClosing(w http.ResponseWriter, r *http.Request) {
	period, err := parsePeriod(r.PathValue("year"), r.PathValue("month"))
	if err != nil {
		writeError(w, r, err)
		return
	}
	closing, err := s.store.MonthClosing(r.Context(), period)
	if err != nil {
		writeError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, closing)
}

func (s *Server) markPaid(w http.ResponseWriter, r *http.Request) {
	period, err := parsePeriod(r.PathValue("year"), r.PathValue("month"))
	if err != nil {
		writeError(w, r, err)
		return
	}
	if err := s.store.MarkPaid(r.Context(), period, r.PathValue("providerID")); err != nil {
		writeError(w, r, err)
		return
	}
	s.respondClosing(w, r, period)
}

func (s *Server) unmarkPaid(w http.ResponseWriter, r *http.Request) {
	period, err := parsePeriod(r.PathValue("year"), r.PathValue("month"))
	if err != nil {
		writeError(w, r, err)
		return
	}
	if err := s.store.UnmarkPaid(r.Context(), period, r.PathValue("providerID")); err != nil {
		writeError(w, r, err)
		return
	}
	s.respondClosing(w, r, period)
}

// respondClosing returns the whole month after a payment change so the client
// can refresh the header total and every card from one response.
func (s *Server) respondClosing(w http.ResponseWriter, r *http.Request, period domain.Period) {
	closing, err := s.store.MonthClosing(r.Context(), period)
	if err != nil {
		writeError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, closing)
}

// ------------------------------------------------------------------ helpers --

func parsePeriod(yearStr, monthStr string) (domain.Period, error) {
	year, err := strconv.Atoi(strings.TrimSpace(yearStr))
	if err != nil {
		return domain.Period{}, domain.Invalid("year %q must be an integer", yearStr)
	}
	month, err := strconv.Atoi(strings.TrimSpace(monthStr))
	if err != nil {
		return domain.Period{}, domain.Invalid("month %q must be an integer", monthStr)
	}
	p := domain.Period{Year: year, Month: month}
	return p, p.Validate()
}

// decode reads a JSON request body, rejecting unknown fields so a typo in a
// client payload fails loudly instead of being silently ignored.
func decode[T any](r *http.Request) (T, error) {
	var out T
	dec := json.NewDecoder(io.LimitReader(r.Body, 1<<20))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&out); err != nil {
		// domain errors from custom unmarshalers (e.g. Date) keep their message.
		var v domain.ErrValidation
		if errors.As(err, &v) {
			return out, v
		}
		return out, domain.Invalid("invalid JSON body: %v", err)
	}
	return out, nil
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		slog.Error("write response", "error", err)
	}
}

// writeError maps domain errors onto status codes. Anything unrecognised is a
// bug on our side: log the detail, tell the client only that it failed.
func writeError(w http.ResponseWriter, r *http.Request, err error) {
	var validation domain.ErrValidation
	switch {
	case errors.Is(err, domain.ErrNotFound):
		writeJSON(w, http.StatusNotFound, errorBody{"not_found", "resource not found"})
	case errors.As(err, &validation):
		writeJSON(w, http.StatusBadRequest, errorBody{"invalid_request", validation.Msg})
	default:
		slog.Error("request failed",
			"method", r.Method, "path", r.URL.Path, "error", err)
		writeJSON(w, http.StatusInternalServerError,
			errorBody{"internal_error", "internal server error"})
	}
}

type errorBody struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}
