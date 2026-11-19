package models

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

// Transaction types
const (
	TxTypeP2PTransfer    = "P2P_TRANSFER"
	TxTypeCardFunding    = "CARD_FUNDING"
	TxTypeCardWithdrawal = "CARD_WITHDRAWAL"
	TxTypeWelcomeDeposit = "WELCOME_DEPOSIT"
	TxTypeCapitalInject  = "CAPITAL_INJECTION"
)

// Account and KYC statuses
const (
	StatusActive = "ACTIVE"
	StatusFrozen = "FROZEN"
	StatusClosed = "CLOSED"

	KYCPending  = "PENDING_KYC"
	KYCVerified = "VERIFIED"
	KYCRejected = "REJECTED"
	KYCFrozen   = "FROZEN"
)

// System account numbers
const (
	SystemAccountTreasury = "2170000000"
	SystemAccountCardPool = "2170000999"
	SystemAccountReserve  = "2170000008"
)

// Database Entities

type User struct {
	UserID       string    `json:"user_id"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"`
	FullName     string    `json:"full_name"`
	Phone        string    `json:"phone"`
	CreatedAt    time.Time `json:"created_at"`
}

type Account struct {
	AccountID     string    `json:"account_id"`
	AccountNumber string    `json:"account_number"`
	UserID        string    `json:"user_id"`
	Currency      string    `json:"currency"`
	Balance       float64   `json:"balance"`
	AccountStatus string    `json:"account_status"`
	TierLevel     int       `json:"tier_level"`
	KYCStatus     string    `json:"kyc_status"`
	IsSystem      int       `json:"is_system"`
	CreatedAt     time.Time `json:"created_at"`
}

type AccountSecurity struct {
	AccountID      string     `json:"account_id"`
	PINHash        string     `json:"pin_hash"`
	FailedAttempts int        `json:"failed_attempts"`
	LockedUntil    *time.Time `json:"locked_until"`
}

type JournalEntry struct {
	JournalID       string    `json:"journal_id"`
	TransactionRef  string    `json:"transaction_ref"`
	IdempotencyKey  string    `json:"idempotency_key"`
	TransactionType string    `json:"transaction_type"`
	Description     string    `json:"description"`
	CreatedAt       time.Time `json:"created_at"`
}

type LedgerPosting struct {
	PostingID      int64     `json:"posting_id"`
	JournalID      string    `json:"journal_id"`
	AccountID      string    `json:"account_id"`
	EntryType      string    `json:"entry_type"` // DEBIT, CREDIT
	Amount         float64   `json:"amount"`
	RunningBalance float64   `json:"running_balance"`
	CreatedAt      time.Time `json:"created_at"`
}

// DTOs for API Responses & Requests

// FlexibleMoney handles both string ("100.00") and number (100.00) in JSON requests
type FlexibleMoney float64

func (m *FlexibleMoney) UnmarshalJSON(b []byte) error {
	str := string(b)
	str = strings.Trim(str, "\"")
	val, err := strconv.ParseFloat(str, 64)
	if err != nil {
		return fmt.Errorf("invalid money amount: %s", string(b))
	}
	*m = FlexibleMoney(val)
	return nil
}

func (m FlexibleMoney) Float64() float64 {
	return float64(m)
}

func FormatMoney(amount float64) string {
	return fmt.Sprintf("%.2f", amount)
}

func TierDailyLimit(tier int) string {
	switch tier {
	case 1:
		return "1000.00"
	case 2:
		return "10000.00"
	default:
		return "UNLIMITED"
	}
}

type UserDTO struct {
	UserID   string `json:"user_id"`
	Email    string `json:"email"`
	FullName string `json:"full_name"`
	Phone    string `json:"phone"`
}

type AccountDTO struct {
	AccountID     string `json:"account_id"`
	AccountNumber string `json:"account_number"`
	UserID        string `json:"user_id"`
	OwnerName     string `json:"owner_name"`
	Currency      string `json:"currency"`
	Balance       string `json:"balance"` // 2-decimal string
	AccountStatus string `json:"account_status"`
	TierLevel     int    `json:"tier_level"`
	KYCStatus     string `json:"kyc_status"`
	DailyLimit    string `json:"daily_limit"`
	CreatedAt     string `json:"created_at"`
}

func ToAccountDTO(acc *Account, ownerName string) *AccountDTO {
	return &AccountDTO{
		AccountID:     acc.AccountID,
		AccountNumber: acc.AccountNumber,
		UserID:        acc.UserID,
		OwnerName:     ownerName,
		Currency:      acc.Currency,
		Balance:       FormatMoney(acc.Balance),
		AccountStatus: acc.AccountStatus,
		TierLevel:     acc.TierLevel,
		KYCStatus:     acc.KYCStatus,
		DailyLimit:    TierDailyLimit(acc.TierLevel),
		CreatedAt:     acc.CreatedAt.Format(time.RFC3339),
	}
}

// API Requests & Responses

type RegisterRequest struct {
	Email    string `json:"email" binding:"required"`
	Password string `json:"password" binding:"required"`
	FullName string `json:"full_name" binding:"required"`
	Phone    string `json:"phone"`
	PIN      string `json:"pin" binding:"required"`
}

type RegisterResponse struct {
	Token   string      `json:"token"`
	User    UserDTO     `json:"user"`
	Account *AccountDTO `json:"account"`
}

type LoginRequest struct {
	Email    string `json:"email" binding:"required"`
	Password string `json:"password" binding:"required"`
}

type LoginResponse struct {
	Token   string      `json:"token"`
	User    UserDTO     `json:"user"`
	Account *AccountDTO `json:"account"`
}

type MeResponse struct {
	User    UserDTO     `json:"user"`
	Account *AccountDTO `json:"account"`
}

type CreateAccountRequest struct {
	UserID         string         `json:"user_id" binding:"required"`
	InitialDeposit *FlexibleMoney `json:"initial_deposit"`
}

type VerifyPINRequest struct {
	PIN string `json:"pin" binding:"required"`
}

type VerifyPINResponse struct {
	Verified bool `json:"verified"`
}

type KYCUpdateRequest struct {
	Status         string `json:"status" binding:"required"` // PENDING_KYC, VERIFIED, REJECTED, FROZEN
	DocumentType   string `json:"document_type"`
	DocumentNumber string `json:"document_number"`
}

type TransferRequest struct {
	IdempotencyKey  string         `json:"idempotency_key" binding:"required"`
	FromAccount     string         `json:"from_account" binding:"required"`
	ToAccount       string         `json:"to_account" binding:"required"`
	Amount          *FlexibleMoney `json:"amount" binding:"required"`
	Description     string         `json:"description"`
	TransactionType string         `json:"transaction_type" binding:"required"`
	PIN             string         `json:"pin"`
}

type TransferResponse struct {
	JournalID        string `json:"journal_id"`
	TransactionRef   string `json:"transaction_ref"`
	TransactionType  string `json:"transaction_type"`
	FromAccount      string `json:"from_account"`
	ToAccount        string `json:"to_account"`
	Amount           string `json:"amount"`
	FromBalanceAfter string `json:"from_balance_after"`
	ToBalanceAfter   string `json:"to_balance_after"`
	CreatedAt        string `json:"created_at"`
	IdempotentReplay bool   `json:"idempotent_replay,omitempty"`
}

type AccountSearchResult struct {
	AccountNumber string `json:"account_number"`
	OwnerName     string `json:"owner_name"`
}

type SearchResponse struct {
	Results []AccountSearchResult `json:"results"`
}

type StatementItem struct {
	PostingID           int64  `json:"posting_id"`
	JournalID           string `json:"journal_id"`
	TransactionRef      string `json:"transaction_ref"`
	TransactionType     string `json:"transaction_type"`
	EntryType           string `json:"entry_type"` // DEBIT, CREDIT
	Amount              string `json:"amount"`
	RunningBalance      string `json:"running_balance"`
	Description         string `json:"description"`
	CounterpartyAccount string `json:"counterparty_account"`
	CounterpartyName    string `json:"counterparty_name"`
	CreatedAt           string `json:"created_at"`
}

type StatementsResponse struct {
	AccountNumber string          `json:"account_number"`
	Page          int             `json:"page"`
	PageSize      int             `json:"page_size"`
	Total         int             `json:"total"`
	Items         []StatementItem `json:"items"`
}

type ErrorResponse struct {
	Error             string `json:"error"`
	Message           string `json:"message"`
	AttemptsRemaining *int   `json:"attempts_remaining,omitempty"`
	LockedUntil       string `json:"locked_until,omitempty"`
}

func (e ErrorResponse) ToMap() map[string]interface{} {
	m := map[string]interface{}{
		"error":   e.Error,
		"message": e.Message,
	}
	if e.AttemptsRemaining != nil {
		m["attempts_remaining"] = *e.AttemptsRemaining
	}
	if e.LockedUntil != "" {
		m["locked_until"] = e.LockedUntil
	}
	return m
}
