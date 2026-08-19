// Package auth handles password hashing and session tokens.
package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"runtime"
	"strings"
	"unicode/utf8"

	"golang.org/x/crypto/argon2"
)

// Argon2id parameters.
//
// These are OWASP's recommended argon2id settings (19 MiB, 2 iterations,
// 1 lane) — chosen over the heavier 64 MiB profile because logins run on a
// small VM and each attempt would otherwise pin 64 MiB. They are recorded in
// every hash string, so raising them later only affects new hashes; existing
// ones keep verifying with the values they were created with.
const (
	argonMemoryKiB = 19456
	argonTime      = 2
	argonThreads   = 1
	argonKeyLen    = 32
	argonSaltLen   = 16
)

// Password length bounds. The maximum exists because argon2 hashes the whole
// input: without a cap, a huge password is a cheap way to burn server CPU.
const (
	MinPasswordLen = 10
	MaxPasswordLen = 1024
)

var (
	ErrPasswordTooShort = fmt.Errorf("a senha precisa ter pelo menos %d caracteres", MinPasswordLen)
	ErrPasswordTooLong  = fmt.Errorf("a senha pode ter no máximo %d caracteres", MaxPasswordLen)
	// ErrInvalidHash means the stored string is not a hash this code wrote.
	ErrInvalidHash = errors.New("malformed password hash")
)

// ValidatePassword applies the length policy. It deliberately does not demand
// character classes: length is what actually resists guessing, and composition
// rules mostly push people toward "Senha123!".
func ValidatePassword(password string) error {
	n := utf8.RuneCountInString(password)
	if n < MinPasswordLen {
		return ErrPasswordTooShort
	}
	if n > MaxPasswordLen {
		return ErrPasswordTooLong
	}
	return nil
}

// HashPassword returns a PHC-format argon2id string, salt included, safe to
// store as-is.
func HashPassword(password string) (string, error) {
	if err := ValidatePassword(password); err != nil {
		return "", err
	}

	salt := make([]byte, argonSaltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("read salt: %w", err)
	}

	key := argon2.IDKey([]byte(password), salt,
		argonTime, argonMemoryKiB, argonThreads, argonKeyLen)

	b64 := base64.RawStdEncoding
	return fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version, argonMemoryKiB, argonTime, argonThreads,
		b64.EncodeToString(salt), b64.EncodeToString(key)), nil
}

// VerifyPassword reports whether password matches encodedHash.
//
// It re-derives using the parameters stored in the hash, so hashes written
// under older settings keep working.
func VerifyPassword(encodedHash, password string) (bool, error) {
	parts := strings.Split(encodedHash, "$")
	// ["", "argon2id", "v=19", "m=..,t=..,p=..", salt, hash]
	if len(parts) != 6 || parts[1] != "argon2id" {
		return false, ErrInvalidHash
	}

	var version int
	if _, err := fmt.Sscanf(parts[2], "v=%d", &version); err != nil {
		return false, ErrInvalidHash
	}
	if version != argon2.Version {
		return false, fmt.Errorf("%w: unsupported version %d", ErrInvalidHash, version)
	}

	var memory uint32
	var time uint32
	var threads uint8
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &memory, &time, &threads); err != nil {
		return false, ErrInvalidHash
	}
	if memory == 0 || time == 0 || threads == 0 {
		return false, ErrInvalidHash
	}
	// A hostile row could otherwise ask for gigabytes and take the process down.
	if memory > 1<<20 {
		return false, fmt.Errorf("%w: memory parameter too large", ErrInvalidHash)
	}

	b64 := base64.RawStdEncoding
	salt, err := b64.DecodeString(parts[4])
	if err != nil {
		return false, ErrInvalidHash
	}
	want, err := b64.DecodeString(parts[5])
	if err != nil {
		return false, ErrInvalidHash
	}

	got := argon2.IDKey([]byte(password), salt,
		time, memory, threads, uint32(len(want)))

	return subtle.ConstantTimeCompare(got, want) == 1, nil
}

// dummyHash is a real argon2id hash of a random password, used by
// [SpendVerifyTime].
var dummyHash string

func init() {
	// Generated once at startup so the cost matches a real verification.
	secret := make([]byte, 32)
	if _, err := rand.Read(secret); err != nil {
		panic("auth: cannot read random bytes: " + err.Error())
	}
	h, err := HashPassword(base64.RawStdEncoding.EncodeToString(secret))
	if err != nil {
		panic("auth: cannot build dummy hash: " + err.Error())
	}
	dummyHash = h
}

// SpendVerifyTime burns roughly the same CPU as a real password check.
//
// Login calls this when the username does not exist, so a wrong username and a
// wrong password take the same time. Without it, response latency tells an
// attacker which usernames are real.
func SpendVerifyTime() {
	_, _ = VerifyPassword(dummyHash, "não importa")
	// Keep the compiler from optimising the call away.
	runtime.KeepAlive(dummyHash)
}
