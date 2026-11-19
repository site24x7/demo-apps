package security_test

import (
	"testing"
	"time"

	"zylkerbank/ledger-service/security"
)

func TestPINHashingAndVerification(t *testing.T) {
	pin := "1234"
	hash, err := security.HashPIN(pin)
	if err != nil {
		t.Fatalf("unexpected error hashing PIN: %v", err)
	}

	valid, err := security.VerifyPIN(pin, hash)
	if err != nil {
		t.Fatalf("unexpected error verifying PIN: %v", err)
	}
	if !valid {
		t.Errorf("expected PIN to verify successfully")
	}

	// Verify wrong PIN fails
	invalid, err := security.VerifyPIN("9999", hash)
	if err != nil {
		t.Fatalf("unexpected error on invalid PIN: %v", err)
	}
	if invalid {
		t.Errorf("expected wrong PIN to fail")
	}

	// Verify deterministic salt
	salt := "0123456789abcdef0123456789abcdef"
	hashDet, err := security.HashPINWithSalt(pin, salt, 120000)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	validDet, err := security.VerifyPIN(pin, hashDet)
	if err != nil || !validDet {
		t.Errorf("expected deterministic hash to verify")
	}
}

func TestPasswordHashingAndVerification(t *testing.T) {
	pass := "Password@123"
	hash, err := security.HashPassword(pass)
	if err != nil {
		t.Fatalf("unexpected error hashing password: %v", err)
	}

	if !security.CheckPassword(pass, hash) {
		t.Errorf("expected password to match hash")
	}
	if security.CheckPassword("WrongPass@123", hash) {
		t.Errorf("expected wrong password to fail")
	}
}

func TestJWTGenerationAndValidation(t *testing.T) {
	secret := "test-jwt-secret-key-1234567890123456"
	userID := "11111111-1111-1111-1111-111111111111"
	email := "alice@zylkerbank.com"
	name := "Alice Johnson"
	accNum := "2170000001"

	token, err := security.GenerateToken(secret, userID, email, name, accNum, 1*time.Hour)
	if err != nil {
		t.Fatalf("failed to generate token: %v", err)
	}

	claims, err := security.ValidateToken(secret, token)
	if err != nil {
		t.Fatalf("failed to validate token: %v", err)
	}

	if claims.UserID != userID || claims.Email != email || claims.Name != name || claims.AccountNumber != accNum {
		t.Errorf("claims mismatch: %+v", claims)
	}

	// Invalid secret validation
	_, err = security.ValidateToken("wrong-secret", token)
	if err == nil {
		t.Errorf("expected error with wrong secret")
	}
}

func TestIsLocked(t *testing.T) {
	if security.IsLocked(nil) {
		t.Errorf("nil lock should not be locked")
	}

	past := time.Now().Add(-1 * time.Minute)
	if security.IsLocked(&past) {
		t.Errorf("past lock should not be locked")
	}

	future := time.Now().Add(15 * time.Minute)
	if !security.IsLocked(&future) {
		t.Errorf("future lock should be locked")
	}
}

func TestSeedHashesVerification(t *testing.T) {
	password := "Password@123"
	seedPasswordHash := "$2a$10$O5EJ9CVnCj6lM9LwYzZ3x.2TVEX.XmUX9scWwWQmJAsbguqtYByDy"
	if !security.CheckPassword(password, seedPasswordHash) {
		t.Errorf("seed password hash failed verification for %s", password)
	}

	pin := "1234"
	seedPINHashes := map[string]string{
		"Alice":   "pbkdf2_sha256$120000$c9bc6cafe7781694f8b33d82cc8cbce6$2cb75893add569c550ee7c034239e35749d04923078fda5df03786c5414d0a6f",
		"Bob":     "pbkdf2_sha256$120000$1468a17d3a9e652cc0da48ac14b4c90d$49d6fa39e7d23d1953235c0dc5aab563aad82cb49fed857247f1e1a4a2b0a6a3",
		"Charlie": "pbkdf2_sha256$120000$d58d46372e0b5660b7a2b62524f13fca$01bd85b27bebab8a6c3953b36c67338a02e481c6bbad62810fa5797e4b7e079d",
	}

	for user, pinHash := range seedPINHashes {
		valid, err := security.VerifyPIN(pin, pinHash)
		if err != nil {
			t.Errorf("unexpected error verifying %s seed PIN hash: %v", user, err)
		}
		if !valid {
			t.Errorf("seed PIN hash failed verification for %s", user)
		}
	}
}
