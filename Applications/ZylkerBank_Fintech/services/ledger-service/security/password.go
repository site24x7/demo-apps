package security

import (
	"golang.org/x/crypto/bcrypt"
)

const BcryptCost = 10

// HashPassword hashes a plaintext password using bcrypt with cost 10
func HashPassword(password string) (string, error) {
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), BcryptCost)
	return string(bytes), err
}

// CheckPassword compares a plaintext password with a bcrypt hash
func CheckPassword(password, hash string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	return err == nil
}
