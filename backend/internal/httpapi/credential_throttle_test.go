package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/felipearaujo/diarias/backend/internal/config"
	"github.com/felipearaujo/diarias/backend/internal/domain"
)

// newTestServer builds a Server with no store. Every case here is rejected by
// the throttle before persistence is reached, which is exactly the property
// being asserted: the limiter runs first.
func newTestServer() *Server {
	return &Server{
		cfg:    config.Config{},
		logins: newLoginLimiter(maxLoginFailures, loginWindow),
	}
}

func postRefresh(t *testing.T, s *Server, token string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/refresh",
		strings.NewReader(`{"refresh_token":"`+token+`"}`))
	req.RemoteAddr = "203.0.113.9:5555"
	rec := httptest.NewRecorder()
	s.refresh(rec, req)
	return rec
}

func TestRefreshIsThrottledAfterRepeatedFailures(t *testing.T) {
	s := newTestServer()
	ipKey := "refresh:ip:203.0.113.9"

	// Simulate the failures the handler would have recorded.
	for range maxLoginFailures {
		s.logins.fail(ipKey)
	}

	rec := postRefresh(t, s, "qualquer-coisa")

	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusTooManyRequests)
	}
	if rec.Header().Get("Retry-After") == "" {
		t.Error("a 429 must tell the caller how long to wait")
	}
	var body errorBody
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if body.Code != "too_many_attempts" {
		t.Errorf("code = %q, want too_many_attempts", body.Code)
	}
}

func TestRefreshThrottleIsSeparateFromLogin(t *testing.T) {
	s := newTestServer()

	// A device stuck refreshing must not consume the budget its owner needs to
	// sign in again and fix the situation.
	for range maxLoginFailures {
		s.logins.fail("refresh:ip:203.0.113.9")
	}

	if ok, _ := s.logins.allow("ip:203.0.113.9"); !ok {
		t.Error("refresh failures locked out login from the same address")
	}
}

func TestRefreshStillValidatesTheBodyBeforeThrottling(t *testing.T) {
	s := newTestServer()

	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/refresh",
		strings.NewReader(`{}`))
	rec := httptest.NewRecorder()
	s.refresh(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}
}

func TestChangePasswordIsThrottled(t *testing.T) {
	s := newTestServer()
	ctx := contextWithUser(t)

	for range maxLoginFailures {
		s.logins.fail("password:felipe")
	}

	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/password",
		strings.NewReader(`{"current_password":"chute","new_password":"nova-senha-longa"}`)).
		WithContext(ctx)
	req.RemoteAddr = "203.0.113.9:5555"
	rec := httptest.NewRecorder()
	s.changePassword(rec, req)

	// Without the guard this would reach the store and brute-forcing the
	// current password would be unbounded.
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusTooManyRequests)
	}
}

func contextWithUser(t *testing.T) context.Context {
	t.Helper()
	return context.WithValue(context.Background(), ctxKeyUser, domain.User{
		ID:       "u1",
		Username: "felipe",
	})
}
