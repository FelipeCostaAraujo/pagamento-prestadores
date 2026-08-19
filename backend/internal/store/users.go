package store

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/felipearaujo/diarias/backend/internal/auth"
	"github.com/felipearaujo/diarias/backend/internal/domain"
)

// ErrUsernameTaken is returned when a username collides, case-insensitively.
var ErrUsernameTaken = errors.New("username already taken")

// ErrInvalidCredentials covers both "no such user" and "wrong password".
// Keeping them indistinguishable stops the API from confirming which usernames
// exist.
var ErrInvalidCredentials = errors.New("invalid credentials")

const usernameMaxLen = 40

// NormalizeUsername trims and lowercases. Usernames are stored as typed but
// matched case-insensitively, so this is what comparisons use.
func NormalizeUsername(username string) string {
	return strings.ToLower(strings.TrimSpace(username))
}

// ValidateUsername keeps usernames to a predictable shape: letters, digits,
// dot, dash and underscore. This avoids look-alike accounts separated only by
// whitespace or invisible characters.
func ValidateUsername(username string) error {
	trimmed := strings.TrimSpace(username)
	if n := utf8.RuneCountInString(trimmed); n < 3 || n > usernameMaxLen {
		return domain.Invalid("o usuário precisa ter entre 3 e %d caracteres", usernameMaxLen)
	}
	for _, r := range trimmed {
		switch {
		case unicode.IsLetter(r), unicode.IsDigit(r):
		case r == '.', r == '-', r == '_':
		default:
			return domain.Invalid("o usuário só pode ter letras, números, ponto, hífen e underline")
		}
	}
	return nil
}

const userCols = `id, username, disabled_at, created_at`

func scanUser(row pgx.Row) (domain.User, error) {
	var u domain.User
	err := row.Scan(&u.ID, &u.Username, &u.DisabledAt, &u.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.User{}, domain.ErrNotFound
	}
	if err != nil {
		return domain.User{}, err
	}
	return u, nil
}

// CreateUser adds an account. The password is hashed here; the plaintext never
// reaches the database layer's SQL.
func (s *Store) CreateUser(ctx context.Context, username, password string) (domain.User, error) {
	if err := ValidateUsername(username); err != nil {
		return domain.User{}, err
	}
	if err := auth.ValidatePassword(password); err != nil {
		return domain.User{}, domain.Invalid("%s", err.Error())
	}

	hash, err := auth.HashPassword(password)
	if err != nil {
		return domain.User{}, fmt.Errorf("hash password: %w", err)
	}

	user, err := scanUser(s.pool.QueryRow(ctx, `
		INSERT INTO users (username, password_hash) VALUES ($1, $2)
		RETURNING `+userCols,
		strings.TrimSpace(username), hash))

	// 23505 = unique_violation, i.e. the lower(username) index.
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		return domain.User{}, ErrUsernameTaken
	}
	if err != nil {
		return domain.User{}, fmt.Errorf("create user: %w", err)
	}
	return user, nil
}

func (s *Store) ListUsers(ctx context.Context) ([]domain.User, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT `+userCols+` FROM users ORDER BY lower(username)`)
	if err != nil {
		return nil, fmt.Errorf("list users: %w", err)
	}
	defer rows.Close()

	users := make([]domain.User, 0, 4)
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			return nil, fmt.Errorf("scan user: %w", err)
		}
		users = append(users, u)
	}
	return users, rows.Err()
}

// SetPassword replaces a user's password and, because the old one may have
// leaked, drops every session that user has open.
func (s *Store) SetPassword(ctx context.Context, username, password string) error {
	if err := auth.ValidatePassword(password); err != nil {
		return domain.Invalid("%s", err.Error())
	}
	hash, err := auth.HashPassword(password)
	if err != nil {
		return fmt.Errorf("hash password: %w", err)
	}

	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var id string
		err := tx.QueryRow(ctx, `
			UPDATE users SET password_hash = $2
			WHERE lower(username) = $1
			RETURNING id`,
			NormalizeUsername(username), hash).Scan(&id)
		if errors.Is(err, pgx.ErrNoRows) {
			return domain.ErrNotFound
		}
		if err != nil {
			return fmt.Errorf("set password: %w", err)
		}
		_, err = tx.Exec(ctx, `DELETE FROM sessions WHERE user_id = $1`, id)
		return err
	})
}

// SetUserDisabled blocks or restores an account. Disabling also revokes any
// session it already has, so access stops immediately rather than at expiry.
func (s *Store) SetUserDisabled(ctx context.Context, username string, disabled bool) error {
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var id string
		err := tx.QueryRow(ctx, `
			UPDATE users
			SET disabled_at = CASE WHEN $2 THEN now() ELSE NULL END
			WHERE lower(username) = $1
			RETURNING id`,
			NormalizeUsername(username), disabled).Scan(&id)
		if errors.Is(err, pgx.ErrNoRows) {
			return domain.ErrNotFound
		}
		if err != nil {
			return fmt.Errorf("set disabled: %w", err)
		}
		if disabled {
			_, err = tx.Exec(ctx, `DELETE FROM sessions WHERE user_id = $1`, id)
		}
		return err
	})
}

// Authenticate checks a username/password pair and returns the user.
//
// Every failure path returns ErrInvalidCredentials and spends comparable CPU,
// so neither the message nor the timing reveals whether the username exists.
func (s *Store) Authenticate(ctx context.Context, username, password string) (domain.User, error) {
	var (
		user domain.User
		hash string
	)
	err := s.pool.QueryRow(ctx, `
		SELECT id, username, disabled_at, created_at, password_hash
		FROM users WHERE lower(username) = $1`,
		NormalizeUsername(username),
	).Scan(&user.ID, &user.Username, &user.DisabledAt, &user.CreatedAt, &hash)

	if errors.Is(err, pgx.ErrNoRows) {
		auth.SpendVerifyTime()
		return domain.User{}, ErrInvalidCredentials
	}
	if err != nil {
		return domain.User{}, fmt.Errorf("load user: %w", err)
	}

	ok, err := auth.VerifyPassword(hash, password)
	if err != nil {
		// A corrupt hash is an operational problem, not a wrong password.
		return domain.User{}, fmt.Errorf("verify password for %q: %w", user.Username, err)
	}
	if !ok {
		return domain.User{}, ErrInvalidCredentials
	}
	// Checked after the password so a disabled account is not detectable
	// without knowing its password.
	if user.DisabledAt != nil {
		return domain.User{}, ErrInvalidCredentials
	}
	return user, nil
}

// CreateSession issues a token for a user. Only the token's digest is stored;
// the returned token is the sole copy.
func (s *Store) CreateSession(ctx context.Context, userID, userAgent string) (domain.Session, error) {
	token, digest, err := auth.NewToken()
	if err != nil {
		return domain.Session{}, err
	}
	expiresAt := time.Now().Add(auth.SessionTTL)

	if len(userAgent) > 200 {
		userAgent = userAgent[:200]
	}

	_, err = s.pool.Exec(ctx, `
		INSERT INTO sessions (token_hash, user_id, expires_at, user_agent)
		VALUES ($1, $2, $3, $4)`,
		digest, userID, expiresAt, userAgent)
	if err != nil {
		return domain.Session{}, fmt.Errorf("create session: %w", err)
	}

	return domain.Session{Token: token, ExpiresAt: expiresAt}, nil
}

// UserForToken resolves a bearer token to its user, or ErrInvalidCredentials.
//
// The expiry check is in the WHERE clause so an expired row can never
// authenticate, even if the sweeper has not removed it yet.
func (s *Store) UserForToken(ctx context.Context, token string) (domain.User, error) {
	var user domain.User
	err := s.pool.QueryRow(ctx, `
		SELECT u.id, u.username, u.disabled_at, u.created_at
		FROM sessions s
		JOIN users u ON u.id = s.user_id
		WHERE s.token_hash = $1
		  AND s.expires_at > now()
		  AND u.disabled_at IS NULL`,
		auth.HashToken(token),
	).Scan(&user.ID, &user.Username, &user.DisabledAt, &user.CreatedAt)

	if errors.Is(err, pgx.ErrNoRows) {
		return domain.User{}, ErrInvalidCredentials
	}
	if err != nil {
		return domain.User{}, fmt.Errorf("load session: %w", err)
	}
	return user, nil
}

// TouchSession records that a token was used. Best-effort: it is only used to
// tell live sessions from abandoned ones, so a failure must not fail the
// request that triggered it.
func (s *Store) TouchSession(ctx context.Context, token string) {
	_, _ = s.pool.Exec(ctx,
		`UPDATE sessions SET last_seen_at = now() WHERE token_hash = $1`,
		auth.HashToken(token))
}

// DeleteSession logs one device out.
func (s *Store) DeleteSession(ctx context.Context, token string) error {
	_, err := s.pool.Exec(ctx,
		`DELETE FROM sessions WHERE token_hash = $1`, auth.HashToken(token))
	if err != nil {
		return fmt.Errorf("delete session: %w", err)
	}
	return nil
}

// DeleteExpiredSessions clears rows that can no longer authenticate.
func (s *Store) DeleteExpiredSessions(ctx context.Context) (int64, error) {
	tag, err := s.pool.Exec(ctx, `DELETE FROM sessions WHERE expires_at <= now()`)
	if err != nil {
		return 0, fmt.Errorf("delete expired sessions: %w", err)
	}
	return tag.RowsAffected(), nil
}

// CountUsers reports how many accounts exist, so the server can warn when it
// is published with none.
func (s *Store) CountUsers(ctx context.Context) (int, error) {
	var n int
	if err := s.pool.QueryRow(ctx, `SELECT count(*) FROM users`).Scan(&n); err != nil {
		return 0, fmt.Errorf("count users: %w", err)
	}
	return n, nil
}
