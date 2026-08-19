package auth

import (
	"strings"
	"testing"
)

const goodPassword = "diarias-marilia-2026"

func TestHashVerifyRoundTrip(t *testing.T) {
	hash, err := HashPassword(goodPassword)
	if err != nil {
		t.Fatalf("HashPassword: %v", err)
	}

	ok, err := VerifyPassword(hash, goodPassword)
	if err != nil {
		t.Fatalf("VerifyPassword: %v", err)
	}
	if !ok {
		t.Error("correct password did not verify")
	}
}

func TestVerifyRejectsWrongPassword(t *testing.T) {
	hash, err := HashPassword(goodPassword)
	if err != nil {
		t.Fatalf("HashPassword: %v", err)
	}

	for _, wrong := range []string{
		goodPassword + "x",
		strings.ToUpper(goodPassword),
		"",
		"diarias-marilia-2025",
	} {
		ok, err := VerifyPassword(hash, wrong)
		if err != nil {
			t.Fatalf("VerifyPassword(%q): %v", wrong, err)
		}
		if ok {
			t.Errorf("wrong password %q verified", wrong)
		}
	}
}

func TestHashIsSaltedPerCall(t *testing.T) {
	first, err := HashPassword(goodPassword)
	if err != nil {
		t.Fatalf("HashPassword: %v", err)
	}
	second, err := HashPassword(goodPassword)
	if err != nil {
		t.Fatalf("HashPassword: %v", err)
	}
	if first == second {
		t.Error("the same password hashed twice produced identical strings; salt is not random")
	}
	// Both must still verify.
	for _, h := range []string{first, second} {
		ok, err := VerifyPassword(h, goodPassword)
		if err != nil || !ok {
			t.Errorf("hash %q failed to verify (ok=%v err=%v)", h, ok, err)
		}
	}
}

func TestHashNeverContainsThePassword(t *testing.T) {
	hash, err := HashPassword(goodPassword)
	if err != nil {
		t.Fatalf("HashPassword: %v", err)
	}
	if strings.Contains(hash, goodPassword) {
		t.Error("hash string contains the plaintext password")
	}
	if !strings.HasPrefix(hash, "$argon2id$v=19$m=") {
		t.Errorf("hash is not in the expected PHC format: %q", hash)
	}
}

func TestVerifyRejectsMalformedHashes(t *testing.T) {
	for name, hash := range map[string]string{
		"empty":           "",
		"not phc":         "hunter2",
		"wrong algorithm": "$argon2i$v=19$m=19456,t=2,p=1$c2FsdA$aGFzaA",
		"missing fields":  "$argon2id$v=19$m=19456,t=2,p=1$c2FsdA",
		"bad version":     "$argon2id$v=16$m=19456,t=2,p=1$c2FsdA$aGFzaA",
		"zero memory":     "$argon2id$v=19$m=0,t=2,p=1$c2FsdA$aGFzaA",
		"bad base64 salt": "$argon2id$v=19$m=19456,t=2,p=1$!!!!$aGFzaA",
		// A hostile row must not be able to make the process allocate GiBs.
		"absurd memory": "$argon2id$v=19$m=99999999,t=2,p=1$c2FsdA$aGFzaA",
	} {
		t.Run(name, func(t *testing.T) {
			ok, err := VerifyPassword(hash, goodPassword)
			if ok {
				t.Error("malformed hash reported a match")
			}
			if err == nil {
				t.Error("expected an error for a malformed hash")
			}
		})
	}
}

func TestValidatePassword(t *testing.T) {
	if err := ValidatePassword(goodPassword); err != nil {
		t.Errorf("valid password rejected: %v", err)
	}
	if err := ValidatePassword("curta"); err == nil {
		t.Error("short password accepted")
	}
	if err := ValidatePassword(strings.Repeat("a", MaxPasswordLen+1)); err == nil {
		t.Error("over-long password accepted")
	}
	// Length is counted in runes, not bytes: 10 accented characters are enough.
	if err := ValidatePassword("çãoçãoçãoç"); err != nil {
		t.Errorf("10-rune password rejected: %v", err)
	}
}

func TestNewTokenIsUniqueAndHashable(t *testing.T) {
	seen := map[string]bool{}
	for range 100 {
		token, digest, err := NewToken()
		if err != nil {
			t.Fatalf("NewToken: %v", err)
		}
		if seen[token] {
			t.Fatal("NewToken returned a duplicate token")
		}
		seen[token] = true

		if len(digest) != 32 {
			t.Errorf("digest is %d bytes, want 32", len(digest))
		}
		if string(digest) != string(HashToken(token)) {
			t.Error("HashToken disagrees with the digest NewToken returned")
		}
		if strings.ContainsAny(token, "+/=") {
			t.Errorf("token %q is not URL-safe base64", token)
		}
	}
}
