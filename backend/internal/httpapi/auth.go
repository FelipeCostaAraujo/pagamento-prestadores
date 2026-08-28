package httpapi

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/felipearaujo/diarias/backend/internal/domain"
	"github.com/felipearaujo/diarias/backend/internal/store"
)

// Login throttling. Counted per username and per client address, so one
// account being hammered does not lock out everyone behind the same proxy, and
// one address spraying many usernames still gets stopped.
const (
	maxLoginFailures = 8
	loginWindow      = 15 * time.Minute
)

type ctxKey int

const (
	ctxKeyUser ctxKey = iota
	ctxKeyToken
)

// userFrom returns the authenticated user. Only valid inside handlers behind
// requireSession.
func userFrom(ctx context.Context) (domain.User, bool) {
	u, ok := ctx.Value(ctxKeyUser).(domain.User)
	return u, ok
}

func tokenFrom(ctx context.Context) string {
	t, _ := ctx.Value(ctxKeyToken).(string)
	return t
}

// bearerToken pulls the credential out of the Authorization header.
func bearerToken(r *http.Request) string {
	header := r.Header.Get("Authorization")
	scheme, value, found := strings.Cut(header, " ")
	if !found || !strings.EqualFold(scheme, "Bearer") {
		return ""
	}
	return strings.TrimSpace(value)
}

// requireSession rejects anything without a valid, unexpired session token and
// attaches the user to the request context.
func (s *Server) requireSession(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := bearerToken(r)
		if token == "" {
			unauthorized(w, "credenciais necessárias")
			return
		}

		user, err := s.store.UserForToken(r.Context(), token)
		if errors.Is(err, store.ErrInvalidCredentials) {
			// Covers expired, revoked and never-existed alike — the client's
			// reaction is the same: log in again.
			unauthorized(w, "sessão inválida ou expirada")
			return
		}
		if err != nil {
			writeError(w, r, err)
			return
		}

		s.store.TouchSession(r.Context(), token)

		ctx := context.WithValue(r.Context(), ctxKeyUser, user)
		ctx = context.WithValue(ctx, ctxKeyToken, token)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func unauthorized(w http.ResponseWriter, message string) {
	w.Header().Set("WWW-Authenticate", `Bearer realm="diarias"`)
	writeJSON(w, http.StatusUnauthorized, errorBody{"unauthorized", message})
}

type loginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type loginResponse struct {
	Token            string      `json:"token"`
	ExpiresAt        time.Time   `json:"expires_at"`
	RefreshToken     string      `json:"refresh_token"`
	RefreshExpiresAt time.Time   `json:"refresh_expires_at"`
	User             domain.User `json:"user"`
}

func sessionResponse(session domain.Session, user domain.User) loginResponse {
	return loginResponse{
		Token:            session.Token,
		ExpiresAt:        session.ExpiresAt,
		RefreshToken:     session.RefreshToken,
		RefreshExpiresAt: session.RefreshExpiresAt,
		User:             user,
	}
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	body, err := decode[loginRequest](r)
	if err != nil {
		writeError(w, r, err)
		return
	}
	if body.Username == "" || body.Password == "" {
		writeError(w, r, domain.Invalid("usuário e senha são obrigatórios"))
		return
	}

	ipKey := "ip:" + clientIP(r, s.cfg.TrustProxy)
	userKey := "user:" + store.NormalizeUsername(body.Username)

	for _, key := range []string{ipKey, userKey} {
		if ok, retryIn := s.logins.allow(key); !ok {
			w.Header().Set("Retry-After", retryAfterSeconds(retryIn))
			writeJSON(w, http.StatusTooManyRequests, errorBody{
				"too_many_attempts",
				"tentativas demais. Tente de novo em alguns minutos.",
			})
			return
		}
	}

	user, err := s.store.Authenticate(r.Context(), body.Username, body.Password)
	if errors.Is(err, store.ErrInvalidCredentials) {
		s.logins.fail(ipKey)
		s.logins.fail(userKey)
		// Logged without the password, and with the username only so a real
		// operator can tell an attack from someone's caps lock.
		slog.Warn("login rejected",
			"username", store.NormalizeUsername(body.Username),
			"ip", clientIP(r, s.cfg.TrustProxy))
		unauthorized(w, "usuário ou senha inválidos")
		return
	}
	if err != nil {
		writeError(w, r, err)
		return
	}

	session, err := s.store.CreateSession(r.Context(), user.ID, r.UserAgent())
	if err != nil {
		writeError(w, r, err)
		return
	}

	s.logins.succeed(ipKey)
	s.logins.succeed(userKey)
	slog.Info("login", "username", user.Username)

	writeJSON(w, http.StatusOK, sessionResponse(session, user))
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

// refresh consumes a refresh token exactly once and rotates the complete token
// pair. It is public because an expired access token cannot pass
// requireSession; possession of the opaque refresh token is the credential.
func (s *Server) refresh(w http.ResponseWriter, r *http.Request) {
	body, err := decode[refreshRequest](r)
	if err != nil {
		writeError(w, r, err)
		return
	}
	if body.RefreshToken == "" {
		writeError(w, r, domain.Invalid("refresh_token is required"))
		return
	}

	session, user, err := s.store.RefreshSession(r.Context(), body.RefreshToken)
	if errors.Is(err, store.ErrInvalidCredentials) {
		unauthorized(w, "refresh token inválido ou expirado")
		return
	}
	if err != nil {
		writeError(w, r, err)
		return
	}

	slog.Info("session refreshed", "username", user.Username)
	writeJSON(w, http.StatusOK, sessionResponse(session, user))
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	if err := s.store.DeleteSession(r.Context(), tokenFrom(r.Context())); err != nil {
		writeError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// me lets the app confirm a stored token is still good on launch, and learn
// who it belongs to.
func (s *Server) me(w http.ResponseWriter, r *http.Request) {
	user, ok := userFrom(r.Context())
	if !ok {
		unauthorized(w, "credenciais necessárias")
		return
	}
	writeJSON(w, http.StatusOK, user)
}

type changePasswordRequest struct {
	CurrentPassword string `json:"current_password"`
	NewPassword     string `json:"new_password"`
}

// changePassword updates the caller's own password. The current password is
// required so a stolen token alone cannot lock the real owner out.
func (s *Server) changePassword(w http.ResponseWriter, r *http.Request) {
	user, ok := userFrom(r.Context())
	if !ok {
		unauthorized(w, "credenciais necessárias")
		return
	}

	body, err := decode[changePasswordRequest](r)
	if err != nil {
		writeError(w, r, err)
		return
	}

	if _, err := s.store.Authenticate(r.Context(), user.Username, body.CurrentPassword); err != nil {
		if errors.Is(err, store.ErrInvalidCredentials) {
			// Authentication itself succeeded in requireSession. A wrong current
			// password is not an expired bearer token, so it must not trigger the
			// client's refresh/logout flow.
			writeJSON(w, http.StatusForbidden,
				errorBody{"invalid_current_password", "senha atual incorreta"})
			return
		}
		writeError(w, r, err)
		return
	}

	// SetPassword drops every session, including this one — the client must
	// log in again, which is the safe behaviour after a credential change.
	if err := s.store.SetPassword(r.Context(), user.Username, body.NewPassword); err != nil {
		writeError(w, r, err)
		return
	}
	slog.Info("password changed", "username", user.Username)
	w.WriteHeader(http.StatusNoContent)
}

func retryAfterSeconds(d time.Duration) string {
	seconds := int(d.Seconds())
	if seconds < 1 {
		seconds = 1
	}
	return strconv.Itoa(seconds)
}
