// Package domain holds the core types shared by the store and the HTTP layer.
//
// All money is integer cents. The JSON field names are the app's wire contract.
package domain

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

// ErrNotFound is returned by the store when a requested row does not exist.
var ErrNotFound = errors.New("not found")

// ErrValidation wraps a caller mistake that should surface as HTTP 400.
type ErrValidation struct{ Msg string }

func (e ErrValidation) Error() string { return e.Msg }

func Invalid(format string, args ...any) error {
	return ErrValidation{Msg: fmt.Sprintf(format, args...)}
}

// dateLayout is the only date representation crossing the wire: a calendar day
// with no timezone, matching Postgres `date`.
const dateLayout = "2006-01-02"

// Date is a timezone-free calendar day that marshals as "2026-08-03".
//
// A plain time.Time would serialise as RFC 3339 and drag a timezone into what
// is fundamentally "the 3rd of August" — a day someone worked, not an instant.
type Date struct{ time.Time }

func NewDate(year int, month time.Month, day int) Date {
	return Date{time.Date(year, month, day, 0, 0, 0, 0, time.UTC)}
}

func ParseDate(s string) (Date, error) {
	t, err := time.ParseInLocation(dateLayout, strings.TrimSpace(s), time.UTC)
	if err != nil {
		return Date{}, Invalid("date %q must be formatted YYYY-MM-DD", s)
	}
	return Date{t}, nil
}

func (d Date) String() string { return d.Format(dateLayout) }

func (d Date) MarshalJSON() ([]byte, error) { return json.Marshal(d.String()) }

func (d *Date) UnmarshalJSON(b []byte) error {
	var s string
	if err := json.Unmarshal(b, &s); err != nil {
		return Invalid("date must be a JSON string formatted YYYY-MM-DD")
	}
	parsed, err := ParseDate(s)
	if err != nil {
		return err
	}
	*d = parsed
	return nil
}

// User is an account that may sign in. There is no role or permission field:
// every user has the same access to the same shared household data.
type User struct {
	ID       string `json:"id"`
	Username string `json:"username"`
	// Non-nil when the account is blocked.
	DisabledAt *time.Time `json:"disabled_at,omitempty"`
	CreatedAt  time.Time  `json:"created_at"`
}

// Session is a successful login or refresh. The raw tokens are populated only
// while issuing the session — storage keeps their SHA-256 digests, never these
// bearer credentials.
type Session struct {
	Token            string    `json:"token"`
	ExpiresAt        time.Time `json:"expires_at"`
	RefreshToken     string    `json:"refresh_token"`
	RefreshExpiresAt time.Time `json:"refresh_expires_at"`
}

// Provider is a prestadora: a person who works day rates.
type Provider struct {
	ID               string    `json:"id"`
	Name             string    `json:"name"`
	DefaultRateCents int64     `json:"default_rate_cents"`
	ColorIndex       int       `json:"color_index"`
	Position         int       `json:"position"`
	CreatedAt        time.Time `json:"created_at"`
	UpdatedAt        time.Time `json:"updated_at"`
}

// WorkEntry is one day a prestadora worked, at the value agreed for that day.
type WorkEntry struct {
	ID         string `json:"id"`
	ProviderID string `json:"provider_id"`
	Date       Date   `json:"date"`
	ValueCents int64  `json:"value_cents"`
}

// ProviderClosing is one prestadora's month: what she worked and whether it
// has been paid.
type ProviderClosing struct {
	Provider   Provider     `json:"provider"`
	EntryCount int          `json:"entry_count"`
	TotalCents int64        `json:"total_cents"`
	Days       []ClosingDay `json:"days"`
	Paid       bool         `json:"paid"`
	// Set only when Paid is true.
	PaidAt          *time.Time `json:"paid_at,omitempty"`
	PaidAmountCents *int64     `json:"paid_amount_cents,omitempty"`
}

type ClosingDay struct {
	Date       Date  `json:"date"`
	ValueCents int64 `json:"value_cents"`
}

// MonthClosing is the payload behind the Fechamento screen.
type MonthClosing struct {
	Year  int `json:"year"`
	Month int `json:"month"`
	// Providers includes every active prestadora, even with zero days, so the
	// screen can show "0 diárias" rather than omitting her.
	Providers []ProviderClosing `json:"providers"`
	// TotalCents is everything worked in the month; OutstandingCents excludes
	// prestadoras already marked as paid and drives the header's "A pagar".
	TotalCents       int64 `json:"total_cents"`
	OutstandingCents int64 `json:"outstanding_cents"`
	WorkedDays       int   `json:"worked_days"`
}

// Period is a year/month pair identifying a closing.
type Period struct {
	Year  int
	Month int
}

func (p Period) Validate() error {
	if p.Year < 1970 || p.Year > 4000 {
		return Invalid("year %d is out of range", p.Year)
	}
	if p.Month < 1 || p.Month > 12 {
		return Invalid("month %d is out of range (1-12)", p.Month)
	}
	return nil
}

// Bounds returns the first day of the period and the first day of the next
// one, for use as a half-open [start, end) range in SQL.
func (p Period) Bounds() (start, end Date) {
	start = NewDate(p.Year, time.Month(p.Month), 1)
	return start, Date{start.AddDate(0, 1, 0)}
}
