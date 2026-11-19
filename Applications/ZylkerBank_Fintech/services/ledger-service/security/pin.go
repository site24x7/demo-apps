package security

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"golang.org/x/crypto/pbkdf2"
)

const (
	PINIterations = 120000
	PINSaltLength = 16
	PINKeyLength  = 32
	PINAlgorithm  = "pbkdf2_sha256"
)

var (
	ErrInvalidPINFormat = errors.New("invalid PIN hash format")
	ErrPINLocked        = errors.New("PIN is locked")
)

// HashPIN generates a formatted PBKDF2 hash: pbkdf2_sha256$<iterations>$<salt_hex>$<hash_hex>
func HashPIN(pin string) (string, error) {
	salt := make([]byte, PINSaltLength)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("failed to generate salt: %w", err)
	}

	dk := pbkdf2.Key([]byte(pin), salt, PINIterations, PINKeyLength, sha256.New)
	saltHex := hex.EncodeToString(salt)
	dkHex := hex.EncodeToString(dk)

	return fmt.Sprintf("%s$%d$%s$%s", PINAlgorithm, PINIterations, saltHex, dkHex), nil
}

// HashPINWithSalt creates a hash with a specific salt and iterations (useful for deterministic seeds/tests)
func HashPINWithSalt(pin string, saltHex string, iterations int) (string, error) {
	salt, err := hex.DecodeString(saltHex)
	if err != nil {
		return "", fmt.Errorf("invalid salt hex: %w", err)
	}
	dk := pbkdf2.Key([]byte(pin), salt, iterations, PINKeyLength, sha256.New)
	return fmt.Sprintf("%s$%d$%s$%s", PINAlgorithm, iterations, saltHex, hex.EncodeToString(dk)), nil
}

// VerifyPIN checks a plaintext PIN against the stored hash
func VerifyPIN(pin, encodedHash string) (bool, error) {
	parts := strings.Split(encodedHash, "$")
	if len(parts) != 4 {
		return false, ErrInvalidPINFormat
	}
	if parts[0] != PINAlgorithm {
		return false, fmt.Errorf("unsupported algorithm: %s", parts[0])
	}

	iterations, err := strconv.Atoi(parts[1])
	if err != nil || iterations <= 0 {
		return false, ErrInvalidPINFormat
	}

	salt, err := hex.DecodeString(parts[2])
	if err != nil {
		return false, ErrInvalidPINFormat
	}

	expectedDK, err := hex.DecodeString(parts[3])
	if err != nil {
		return false, ErrInvalidPINFormat
	}

	actualDK := pbkdf2.Key([]byte(pin), salt, iterations, len(expectedDK), sha256.New)

	if subtle.ConstantTimeCompare(actualDK, expectedDK) == 1 {
		return true, nil
	}
	return false, nil
}

// IsLocked checks whether an account's PIN verification is currently locked
func IsLocked(lockedUntil *time.Time) bool {
	if lockedUntil == nil {
		return false
	}
	return time.Now().Before(*lockedUntil)
}
