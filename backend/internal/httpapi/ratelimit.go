package httpapi

import (
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

// loginLimiter throttles failed logins.
//
// It is deliberately in-memory: this deployment is a single API container, so
// there is nothing to share state with, and a counter that resets on restart is
// far better than no counter at all. If the API is ever scaled past one
// replica, this needs to move to Postgres or Redis to stay effective.
type loginLimiter struct {
	mu      sync.Mutex
	buckets map[string]*loginBucket

	max    int
	window time.Duration
}

type loginBucket struct {
	failures int
	resetAt  time.Time
}

func newLoginLimiter(max int, window time.Duration) *loginLimiter {
	return &loginLimiter{
		buckets: make(map[string]*loginBucket),
		max:     max,
		window:  window,
	}
}

// allow reports whether another attempt may be made for key, and if not, how
// long the caller must wait.
func (l *loginLimiter) allow(key string) (bool, time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := time.Now()
	b, ok := l.buckets[key]
	if !ok || now.After(b.resetAt) {
		return true, 0
	}
	if b.failures < l.max {
		return true, 0
	}
	return false, b.resetAt.Sub(now)
}

// fail records a rejected attempt. The window restarts on every failure, so a
// steady trickle of guesses keeps the caller locked out rather than letting it
// drip past the limit.
func (l *loginLimiter) fail(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := time.Now()
	l.sweepLocked(now)

	b, ok := l.buckets[key]
	if !ok || now.After(b.resetAt) {
		l.buckets[key] = &loginBucket{failures: 1, resetAt: now.Add(l.window)}
		return
	}
	b.failures++
	b.resetAt = now.Add(l.window)
}

// succeed clears the counter after a correct password.
func (l *loginLimiter) succeed(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.buckets, key)
}

// sweepLocked drops expired buckets so the map cannot grow without bound from
// attempts against many different usernames. Callers must hold the mutex.
func (l *loginLimiter) sweepLocked(now time.Time) {
	if len(l.buckets) < 1024 {
		return
	}
	for k, b := range l.buckets {
		if now.After(b.resetAt) {
			delete(l.buckets, k)
		}
	}
}

// clientIP extracts the caller's address, trusting X-Forwarded-For only when
// the server is configured to sit behind a proxy.
//
// Trusting the header unconditionally would let anyone forge it and sidestep
// per-IP throttling entirely, so it is opt-in via DIARIAS_TRUST_PROXY.
func clientIP(r *http.Request, trustProxy bool) string {
	if trustProxy {
		if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
			// Left-most entry is the original client; the rest are proxies.
			if first, _, found := strings.Cut(xff, ","); found {
				return strings.TrimSpace(first)
			}
			return strings.TrimSpace(xff)
		}
		if real := strings.TrimSpace(r.Header.Get("X-Real-IP")); real != "" {
			return real
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
