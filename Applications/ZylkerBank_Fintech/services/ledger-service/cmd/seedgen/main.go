package main

import (
	"fmt"
	"log"

	"zylkerbank/ledger-service/security"
)

func main() {
	pass := "Password@123"
	passHash, err := security.HashPassword(pass)
	if err != nil {
		log.Fatalf("failed to hash password: %v", err)
	}
	fmt.Printf("Bcrypt hash for '%s':\n%s\n\n", pass, passHash)

	pin := "1234"
	for i, user := range []string{"Alice", "Bob", "Charlie"} {
		pinHash, err := security.HashPIN(pin)
		if err != nil {
			log.Fatalf("failed to hash pin for %s: %v", user, err)
		}
		fmt.Printf("PBKDF2 PIN hash for %s (%s):\n%s\n", user, pin, pinHash)
		// Verify immediately
		ok, err := security.VerifyPIN(pin, pinHash)
		if !ok || err != nil {
			log.Fatalf("verification failed for %s", user)
		}
		_ = i
	}
}
