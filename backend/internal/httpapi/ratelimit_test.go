package httpapi

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestLimiterBlocksAfterMaxFailures(t *testing.T) {
	l := newLoginLimiter(3, time.Minute)

	for i := range 3 {
		if ok, _ := l.allow("user:felipe"); !ok {
			t.Fatalf("attempt %d blocked before the limit was reached", i+1)
		}
		l.fail("user:felipe")
	}

	ok, retryIn := l.allow("user:felipe")
	if ok {
		t.Error("attempt allowed after the limit was reached")
	}
	if retryIn <= 0 {
		t.Errorf("retryIn = %v, want a positive wait", retryIn)
	}
}

func TestLimiterKeysAreIndependent(t *testing.T) {
	l := newLoginLimiter(2, time.Minute)

	for range 3 {
		l.fail("user:felipe")
	}

	if ok, _ := l.allow("user:felipe"); ok {
		t.Error("locked-out key was allowed")
	}
	// Another account must not be affected by someone else's failures.
	if ok, _ := l.allow("user:marilia"); !ok {
		t.Error("an unrelated key was locked out")
	}
}

func TestLimiterResetsOnSuccess(t *testing.T) {
	l := newLoginLimiter(2, time.Minute)

	l.fail("ip:10.0.0.1")
	l.fail("ip:10.0.0.1")
	if ok, _ := l.allow("ip:10.0.0.1"); ok {
		t.Fatal("expected the key to be locked out")
	}

	l.succeed("ip:10.0.0.1")
	if ok, _ := l.allow("ip:10.0.0.1"); !ok {
		t.Error("a correct password did not clear the counter")
	}
}

func TestLimiterForgetsAfterTheWindow(t *testing.T) {
	// A window already in the past stands in for waiting it out.
	l := newLoginLimiter(1, time.Nanosecond)

	l.fail("user:felipe")
	time.Sleep(2 * time.Millisecond)

	if ok, _ := l.allow("user:felipe"); !ok {
		t.Error("key still locked out after its window elapsed")
	}
}

func TestClientIPIgnoresForwardedHeaderUnlessTrusted(t *testing.T) {
	r := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", nil)
	r.RemoteAddr = "192.168.10.26:54321"
	r.Header.Set("X-Forwarded-For", "203.0.113.9")

	// Untrusted: a caller could otherwise forge a new address per attempt and
	// never hit the per-IP limit.
	if got := clientIP(r, false); got != "192.168.10.26" {
		t.Errorf("clientIP(trustProxy=false) = %q, want the socket address", got)
	}
	if got := clientIP(r, true); got != "203.0.113.9" {
		t.Errorf("clientIP(trustProxy=true) = %q, want the forwarded address", got)
	}
}

func TestClientIPTakesTheOriginalClientFromAChain(t *testing.T) {
	r := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", nil)
	r.RemoteAddr = "10.0.0.5:443"
	r.Header.Set("X-Forwarded-For", "203.0.113.9, 70.41.3.18, 150.172.238.178")

	if got := clientIP(r, true); got != "203.0.113.9" {
		t.Errorf("clientIP = %q, want the left-most entry", got)
	}
}
