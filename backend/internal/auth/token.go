package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"time"
)

const (
	// AccessTokenTTL keeps the bearer credential sent on every API request
	// short-lived. The app can transparently replace it with the refresh token.
	AccessTokenTTL = 15 * time.Minute

	// RefreshTokenTTL is the maximum lifetime of a login. Refresh rotation does
	// not extend it, so an active device still has to authenticate every 30 days.
	RefreshTokenTTL = 30 * 24 * time.Hour
)

// tokenBytes is the entropy in a session token. 32 bytes of CSPRNG output is
// far beyond guessing, which is why the database can store a plain SHA-256 of
// it rather than a slow hash.
const tokenBytes = 32

// NewToken returns a fresh opaque session token and its digest. The token goes
// to the client and is never persisted; only the digest is stored.
func NewToken() (token string, digest []byte, err error) {
	raw := make([]byte, tokenBytes)
	if _, err := rand.Read(raw); err != nil {
		return "", nil, fmt.Errorf("read token bytes: %w", err)
	}
	token = base64.RawURLEncoding.EncodeToString(raw)
	return token, HashToken(token), nil
}

// HashToken digests a token for lookup. Callers compare by looking the digest
// up as a primary key, so no constant-time compare is needed: the database
// index does an equality match on a value the attacker cannot influence
// without already knowing the token.
func HashToken(token string) []byte {
	sum := sha256.Sum256([]byte(token))
	return sum[:]
}
