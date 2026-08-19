package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"time"
)

// SessionTTL is how long a login stays valid. Long enough that a phone app is
// not asking for the password every week, short enough that a leaked token
// stops working.
const SessionTTL = 30 * 24 * time.Hour

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
