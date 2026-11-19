package service

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"

	"zylkerbank/ledger-service/db"
	"zylkerbank/ledger-service/models"
)

var (
	ErrInvalidAmount      = errors.New("INVALID_AMOUNT")
	ErrSameAccount        = errors.New("SAME_ACCOUNT")
	ErrInvalidTxType      = errors.New("INVALID_TRANSACTION_TYPE")
	ErrAccountFrozen      = errors.New("ACCOUNT_FROZEN")
	ErrKYCNotVerified     = errors.New("KYC_NOT_VERIFIED")
	ErrDailyLimitExceeded = errors.New("DAILY_LIMIT_EXCEEDED")
	ErrInsufficientFunds  = errors.New("INSUFFICIENT_FUNDS")
)

type CustomError struct {
	Code              string
	Message           string
	Status            int
	AttemptsRemaining *int
	LockedUntil       *time.Time
}

func (e *CustomError) Error() string {
	return e.Message
}

type LedgerService struct {
	repo           db.Repository
	accountService *AccountService
}

func NewLedgerService(repo db.Repository, accountService *AccountService) *LedgerService {
	return &LedgerService{
		repo:           repo,
		accountService: accountService,
	}
}

func (s *LedgerService) Transfer(ctx context.Context, req models.TransferRequest) (*models.TransferResponse, error) {
	// 1. Idempotency Check
	existingJournal, postings, err := s.repo.GetJournalByIdempotencyKey(ctx, req.IdempotencyKey)
	if err == nil && existingJournal != nil {
		// Replay existing transaction
		var fromPost, toPost *models.LedgerPosting
		for i := range postings {
			if postings[i].EntryType == "DEBIT" {
				fromPost = &postings[i]
			} else if postings[i].EntryType == "CREDIT" {
				toPost = &postings[i]
			}
		}

		fromBalStr := ""
		toBalStr := ""
		if fromPost != nil {
			fromBalStr = models.FormatMoney(fromPost.RunningBalance)
		}
		if toPost != nil {
			toBalStr = models.FormatMoney(toPost.RunningBalance)
		}

		return &models.TransferResponse{
			JournalID:        existingJournal.JournalID,
			TransactionRef:   existingJournal.TransactionRef,
			TransactionType:  existingJournal.TransactionType,
			FromAccount:      req.FromAccount,
			ToAccount:        req.ToAccount,
			Amount:           models.FormatMoney(req.Amount.Float64()),
			FromBalanceAfter: fromBalStr,
			ToBalanceAfter:   toBalStr,
			CreatedAt:        existingJournal.CreatedAt.Format(time.RFC3339),
			IdempotentReplay: true,
		}, nil
	} else if err != nil && !errors.Is(err, db.ErrNotFound) {
		return nil, fmt.Errorf("failed to check idempotency: %w", err)
	}

	// 2. Basic validations
	if req.Amount == nil || req.Amount.Float64() <= 0 {
		return nil, ErrInvalidAmount
	}
	amount := req.Amount.Float64()

	if req.FromAccount == req.ToAccount {
		return nil, ErrSameAccount
	}

	switch req.TransactionType {
	case models.TxTypeP2PTransfer, models.TxTypeCardFunding, models.TxTypeCardWithdrawal, models.TxTypeWelcomeDeposit:
		// valid
	default:
		return nil, ErrInvalidTxType
	}

	// 3. Lookup source and destination accounts
	fromAcc, _, err := s.repo.GetAccountByNumber(ctx, req.FromAccount)
	if err != nil {
		if errors.Is(err, db.ErrNotFound) {
			return nil, ErrAccountNotFound
		}
		return nil, err
	}

	toAcc, _, err := s.repo.GetAccountByNumber(ctx, req.ToAccount)
	if err != nil {
		if errors.Is(err, db.ErrNotFound) {
			return nil, ErrAccountNotFound
		}
		return nil, err
	}

	// 4. Check Frozen status
	if fromAcc.AccountStatus == models.StatusFrozen || toAcc.AccountStatus == models.StatusFrozen {
		return nil, ErrAccountFrozen
	}

	// 5. Check KYC status for non-system accounts
	if fromAcc.IsSystem == 0 && fromAcc.KYCStatus != models.KYCVerified {
		return nil, ErrKYCNotVerified
	}
	if toAcc.IsSystem == 0 && toAcc.KYCStatus != models.KYCVerified {
		return nil, ErrKYCNotVerified
	}

	// 6. PIN verification (required iff from_account is not a system account)
	if fromAcc.IsSystem == 0 {
		if req.PIN == "" {
			return nil, ErrInvalidPIN
		}

		verified, attemptsRemaining, lockedUntil, err := s.accountService.VerifyPIN(ctx, fromAcc.AccountNumber, req.PIN)
		if err != nil {
			if errors.Is(err, ErrPINLocked) {
				return nil, &CustomError{
					Code:        "PIN_LOCKED",
					Message:     "PIN is locked due to too many failed attempts",
					Status:      423,
					LockedUntil: lockedUntil,
				}
			}
			if errors.Is(err, ErrInvalidPIN) {
				rem := attemptsRemaining
				return nil, &CustomError{
					Code:              "INVALID_PIN",
					Message:           "Invalid security PIN",
					Status:            401,
					AttemptsRemaining: &rem,
				}
			}
			return nil, err
		}
		if !verified {
			rem := attemptsRemaining
			return nil, &CustomError{
				Code:              "INVALID_PIN",
				Message:           "Invalid security PIN",
				Status:            401,
				AttemptsRemaining: &rem,
			}
		}
	}

	// 7. Tier Daily Debit Limit check (P2P_TRANSFER only)
	if req.TransactionType == models.TxTypeP2PTransfer && fromAcc.IsSystem == 0 {
		var dailyLimit float64
		switch fromAcc.TierLevel {
		case 1:
			dailyLimit = 1000.00
		case 2:
			dailyLimit = 10000.00
		default:
			dailyLimit = -1.0 // unlimited
		}

		if dailyLimit > 0 {
			todayDebits, err := s.repo.GetDailyP2PDebitTotal(ctx, fromAcc.AccountID)
			if err != nil {
				return nil, fmt.Errorf("failed to check daily limits: %w", err)
			}
			if todayDebits+amount > dailyLimit {
				return nil, ErrDailyLimitExceeded
			}
		}
	}

	// 8. Pre-check balance before beginning transaction (optimistic check)
	if fromAcc.Balance < amount {
		return nil, ErrInsufficientFunds
	}

	// 9. Execute transfer inside DB transaction with SELECT ... FOR UPDATE
	txRef := fmt.Sprintf("TRN-%s-%s", time.Now().Format("20060102150405"), uuid.NewString()[:8])
	journal := &models.JournalEntry{
		JournalID:       uuid.NewString(),
		TransactionRef:  txRef,
		IdempotencyKey:  req.IdempotencyKey,
		TransactionType: req.TransactionType,
		Description:     req.Description,
	}

	debitPost, creditPost, err := s.repo.ExecuteTransferTx(ctx, fromAcc.AccountID, toAcc.AccountID, amount, journal)
	if err != nil {
		if errors.Is(err, db.ErrInsufficientFunds) {
			return nil, ErrInsufficientFunds
		}
		if errors.Is(err, db.ErrAccountFrozen) {
			return nil, ErrAccountFrozen
		}
		if errors.Is(err, db.ErrDuplicateKey) {
			// Idempotent collision during concurrent request
			return s.Transfer(ctx, req)
		}
		return nil, fmt.Errorf("transfer transaction failed: %w", err)
	}

	return &models.TransferResponse{
		JournalID:        journal.JournalID,
		TransactionRef:   journal.TransactionRef,
		TransactionType:  journal.TransactionType,
		FromAccount:      req.FromAccount,
		ToAccount:        req.ToAccount,
		Amount:           models.FormatMoney(amount),
		FromBalanceAfter: models.FormatMoney(debitPost.RunningBalance),
		ToBalanceAfter:   models.FormatMoney(creditPost.RunningBalance),
		CreatedAt:        debitPost.CreatedAt.Format(time.RFC3339),
		IdempotentReplay: false,
	}, nil
}

func (s *LedgerService) GetStatements(
	ctx context.Context,
	accNum string,
	page, pageSize int,
	fromDate, toDate *time.Time,
) (*models.StatementsResponse, error) {
	// Verify account exists
	_, _, err := s.repo.GetAccountByNumber(ctx, accNum)
	if err != nil {
		if errors.Is(err, db.ErrNotFound) {
			return nil, ErrAccountNotFound
		}
		return nil, err
	}

	items, total, err := s.repo.GetStatements(ctx, accNum, page, pageSize, fromDate, toDate)
	if err != nil {
		return nil, err
	}

	return &models.StatementsResponse{
		AccountNumber: accNum,
		Page:          page,
		PageSize:      pageSize,
		Total:         total,
		Items:         items,
	}, nil
}
