package domain

import (
	"encoding/json"
	"testing"
	"time"
)

func TestDateJSONRoundTrip(t *testing.T) {
	type payload struct {
		Date Date `json:"date"`
	}

	raw := `{"date":"2026-08-03"}`
	var got payload
	if err := json.Unmarshal([]byte(raw), &got); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if want := "2026-08-03"; got.Date.String() != want {
		t.Errorf("parsed date = %q, want %q", got.Date.String(), want)
	}

	out, err := json.Marshal(got)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if string(out) != raw {
		t.Errorf("re-marshalled = %s, want %s", out, raw)
	}
}

func TestDateRejectsBadInput(t *testing.T) {
	for _, in := range []string{
		`{"date":"03/08/2026"}`,        // Brazilian display format, not wire format
		`{"date":"2026-08-03T00:00Z"}`, // full timestamp
		`{"date":"2026-13-01"}`,        // month out of range
		`{"date":17}`,                  // not a string
	} {
		var got struct {
			Date Date `json:"date"`
		}
		if err := json.Unmarshal([]byte(in), &got); err == nil {
			t.Errorf("unmarshal(%s) succeeded, want error", in)
		}
	}
}

func TestPeriodBoundsIsHalfOpen(t *testing.T) {
	tests := []struct {
		period     Period
		start, end string
	}{
		{Period{2026, 8}, "2026-08-01", "2026-09-01"},
		// December must roll the year over, not produce month 13.
		{Period{2026, 12}, "2026-12-01", "2027-01-01"},
		// February in a leap year: end is 1 March either way.
		{Period{2024, 2}, "2024-02-01", "2024-03-01"},
	}

	for _, tt := range tests {
		start, end := tt.period.Bounds()
		if start.String() != tt.start || end.String() != tt.end {
			t.Errorf("Period{%d,%d}.Bounds() = [%s, %s), want [%s, %s)",
				tt.period.Year, tt.period.Month,
				start, end, tt.start, tt.end)
		}
	}
}

func TestPeriodBoundsCoversEveryDay(t *testing.T) {
	// A 31-day month must expose exactly 31 days inside [start, end).
	start, end := Period{2026, 7}.Bounds()
	days := int(end.Sub(start.Time) / (24 * time.Hour))
	if days != 31 {
		t.Errorf("July 2026 spans %d days, want 31", days)
	}
}

func TestPeriodValidate(t *testing.T) {
	valid := []Period{{2026, 1}, {2026, 12}, {1970, 6}}
	for _, p := range valid {
		if err := p.Validate(); err != nil {
			t.Errorf("Period{%d,%d} rejected: %v", p.Year, p.Month, err)
		}
	}

	invalid := []Period{{2026, 0}, {2026, 13}, {1969, 5}, {4001, 5}}
	for _, p := range invalid {
		if err := p.Validate(); err == nil {
			t.Errorf("Period{%d,%d} accepted, want error", p.Year, p.Month)
		}
	}
}
