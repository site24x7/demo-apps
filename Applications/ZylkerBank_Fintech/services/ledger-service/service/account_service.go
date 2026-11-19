package service

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"time"

	"github.com/google/uuid"

	"zylkerbank/ledger-service/config"
	"zylkerbank/ledger-service/db"
	"zylkerbank/ledger-service/models"
	"zylkerbank/ledger-service/security"
)

var (
	ErrEmailExists        = errors.New("EMAIL_EXISTS")
	ErrInvalidCredentials = errors.New("INVALID_CREDENTIALS")
	ErrAccountNotFound    = errors.New("ACCOUNT_NOT_FOUND")
	ErrInvalidPIN         = errors.New("INVALID_PIN")
	ErrPINLocked          = errors.New("PIN_LOCKED")
	ErrInvalidPINFormat   = errors.New("INVALID_PIN_FORMAT")
	ErrInvalidKYCStatus   = errors.New("INVALID_KYC_STATUS")
)

var pinRegex = regexp.MustCompile(`^[0-9]{4,6}$`)

type AccountService struct {
	repo db.Repository
	cfg  *config.Config
}

func NewAccountService(repo db.Repository, cfg *config.Config) *AccountService {
	return &AccountService{
		repo: repo,
		cfg:  cfg,
	}
}

func (s *AccountService) Register(ctx context.Context, req models.RegisterRequest) (*models.RegisterResponse, error) {
	// Validate PIN
	if !pinRegex.MatchString(req.PIN) {
		return nil, ErrInvalidPINFormat
	}

	// Check if user already exists
	_, err := s.repo.GetUserByEmail(ctx, req.Email)
	if err == nil {
		return nil, ErrEmailExists
	} else if !errors.Is(err, db.ErrNotFound) {
		return nil, fmt.Errorf("failed to check email: %w", err)
	}

	// Hash password
	passHash, err := security.HashPassword(req.Password)
	if err != nil {
		return nil, fmt.Errorf("failed to hash password: %w", err)
	}

	userID := uuid.NewString()
	user := &models.User{
		UserID:       userID,
		Email:        req.Email,
		PasswordHash: passHash,
		FullName:     req.FullName,
		Phone:        req.Phone,
	}

	if err := s.repo.CreateUser(ctx, user); err != nil {
		if errors.Is(err, db.ErrDuplicateKey) {
			return nil, ErrEmailExists
		}
		return nil, fmt.Errorf("failed to create user: %w", err)
	}

	// Generate account number
	accNum, err := s.repo.GetNextAccountNumber(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to allocate account number: %w", err)
	}

	kycStatus := models.KYCVerified
	if !s.cfg.KYCAutoApprove {
		kycStatus = models.KYCPending
	}

	accountID := uuid.NewString()
	acc := &models.Account{
		AccountID:     accountID,
		AccountNumber: accNum,
		UserID:        userID,
		Currency:      "USD",
		Balance:       0.00,
		AccountStatus: models.StatusActive,
		TierLevel:     1,
		KYCStatus:     kycStatus,
		IsSystem:      0,
	}

	if err := s.repo.CreateAccount(ctx, acc); err != nil {
		return nil, fmt.Errorf("failed to create account: %w", err)
	}

	// Hash PIN and store in account_security
	pinHash, err := security.HashPIN(req.PIN)
	if err != nil {
		return nil, fmt.Errorf("failed to hash PIN: %w", err)
	}

	sec := &models.AccountSecurity{
		AccountID:      accountID,
		PINHash:        pinHash,
		FailedAttempts: 0,
		LockedUntil:    nil,
	}
	if err := s.repo.CreateAccountSecurity(ctx, sec); err != nil {
		return nil, fmt.Errorf("failed to create account security: %w", err)
	}

	// Welcome deposit from Treasury if configured
	if s.cfg.WelcomeDeposit > 0 {
		treasuryAcc, _, err := s.repo.GetAccountByNumber(ctx, models.SystemAccountTreasury)
		if err == nil && treasuryAcc != nil {
			journal := &models.JournalEntry{
				JournalID:       uuid.NewString(),
				TransactionRef:  fmt.Sprintf("TRN-WELCOME-%s", uuid.NewString()[:8]),
				IdempotencyKey:  fmt.Sprintf("WELCOME-DEP-%s", accountID),
				TransactionType: models.TxTypeWelcomeDeposit,
				Description:     "Welcome deposit bonus",
			}
			_, _, err = s.repo.ExecuteTransferTx(ctx, treasuryAcc.AccountID, accountID, s.cfg.WelcomeDeposit, journal)
			if err == nil {
				acc.Balance = s.cfg.WelcomeDeposit
			}
		}
	}

	token, err := security.GenerateToken(
		s.cfg.JWTSecret,
		userID,
		user.Email,
		user.FullName,
		acc.AccountNumber,
		24*time.Hour,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to generate JWT: %w", err)
	}

	return &models.RegisterResponse{
		Token: token,
		User: models.UserDTO{
			UserID:   user.UserID,
			Email:    user.Email,
			FullName: user.FullName,
			Phone:    user.Phone,
		},
		Account: models.ToAccountDTO(acc, user.FullName),
	}, nil
}

func (s *AccountService) Login(ctx context.Context, req models.LoginRequest) (*models.LoginResponse, error) {
	user, err := s.repo.GetUserByEmail(ctx, req.Email)
	if err != nil {
		if errors.Is(err, db.ErrNotFound) {
			return nil, ErrInvalidCredentials
		}
		return nil, fmt.Errorf("failed to fetch user: %w", err)
	}

	if !security.CheckPassword(req.Password, user.PasswordHash) {
		return nil, ErrInvalidCredentials
	}

	acc, _, err := s.repo.GetAccountByUserID(ctx, user.UserID)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch account for user: %w", err)
	}

	token, err := security.GenerateToken(
		s.cfg.JWTSecret,
		user.UserID,
		user.Email,
		user.FullName,
		acc.AccountNumber,
		24*time.Hour,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to generate JWT: %w", err)
	}

	return &models.LoginResponse{
		Token: token,
		User: models.UserDTO{
			UserID:   user.UserID,
			Email:    user.Email,
			FullName: user.FullName,
			Phone:    user.Phone,
		},
		Account: models.ToAccountDTO(acc, user.FullName),
	}, nil
}

func (s *AccountService) GetAccountByNumber(ctx context.Context, accNum string) (*models.AccountDTO, error) {
	acc, user, err := s.repo.GetAccountByNumber(ctx, accNum)
	if err != nil {
		if errors.Is(err, db.ErrNotFound) {
			return nil, ErrAccountNotFound
		}
		return nil, err
	}
	return models.ToAccountDTO(acc, user.FullName), nil
}

func (s *AccountService) GetAccountByUserID(ctx context.Context, userID string) (*models.AccountDTO, *models.UserDTO, error) {
	acc, user, err := s.repo.GetAccountByUserID(ctx, userID)
	if err != nil {
		if errors.Is(err, db.ErrNotFound) {
			return nil, nil, ErrAccountNotFound
		}
		return nil, nil, err
	}
	uDTO := &models.UserDTO{
		UserID:   user.UserID,
		Email:    user.Email,
		FullName: user.FullName,
		Phone:    user.Phone,
	}
	return models.ToAccountDTO(acc, user.FullName), uDTO, nil
}

func (s *AccountService) CreateAccount(ctx context.Context, req models.CreateAccountRequest) (*models.AccountDTO, error) {
	user, err := s.repo.GetUserByID(ctx, req.UserID)
	if err != nil {
		if errors.Is(err, db.ErrNotFound) {
			return nil, errors.New("USER_NOT_FOUND")
		}
		return nil, err
	}

	accNum, err := s.repo.GetNextAccountNumber(ctx)
	if err != nil {
		return nil, err
	}

	accID := uuid.NewString()
	acc := &models.Account{
		AccountID:     accID,
		AccountNumber: accNum,
		UserID:        user.UserID,
		Currency:      "USD",
		Balance:       0.00,
		AccountStatus: models.StatusActive,
		TierLevel:     1,
		KYCStatus:     models.KYCVerified,
		IsSystem:      0,
	}

	if err := s.repo.CreateAccount(ctx, acc); err != nil {
		return nil, err
	}

	if req.InitialDeposit != nil && req.InitialDeposit.Float64() > 0 {
		treasuryAcc, _, err := s.repo.GetAccountByNumber(ctx, models.SystemAccountTreasury)
		if err == nil && treasuryAcc != nil {
			journal := &models.JournalEntry{
				JournalID:       uuid.NewString(),
				TransactionRef:  fmt.Sprintf("TRN-INIT-%s", uuid.NewString()[:8]),
				IdempotencyKey:  fmt.Sprintf("INIT-DEP-%s", accID),
				TransactionType: models.TxTypeWelcomeDeposit,
				Description:     "Initial account deposit",
			}
			_, _, err = s.repo.ExecuteTransferTx(ctx, treasuryAcc.AccountID, accID, req.InitialDeposit.Float64(), journal)
			if err == nil {
				acc.Balance = req.InitialDeposit.Float64()
			}
		}
	}

	return models.ToAccountDTO(acc, user.FullName), nil
}

func (s *AccountService) VerifyPIN(ctx context.Context, accNum, pin string) (bool, int, *time.Time, error) {
	acc, _, err := s.repo.GetAccountByNumber(ctx, accNum)
	if err != nil {
		if errors.Is(err, db.ErrNotFound) {
			return false, 0, nil, ErrAccountNotFound
		}
		return false, 0, nil, err
	}

	sec, err := s.repo.GetAccountSecurity(ctx, acc.AccountID)
	if err != nil {
		return false, 0, nil, fmt.Errorf("failed to fetch security settings: %w", err)
	}

	// Check if already locked
	if security.IsLocked(sec.LockedUntil) {
		return false, 0, sec.LockedUntil, ErrPINLocked
	}

	// Verify PIN
	matched, err := security.VerifyPIN(pin, sec.PINHash)
	if err != nil {
		return false, 0, nil, err
	}

	if matched {
		// Reset failed attempts on success
		if sec.FailedAttempts > 0 || sec.LockedUntil != nil {
			sec.FailedAttempts = 0
			sec.LockedUntil = nil
			_ = s.repo.UpdateAccountSecurity(ctx, sec)
		}
		return true, 3, nil, nil
	}

	// Mismatch: increment failed attempts
	sec.FailedAttempts++
	if sec.FailedAttempts >= 3 {
		lockUntil := time.Now().Add(15 * time.Minute)
		sec.LockedUntil = &lockUntil
		_ = s.repo.UpdateAccountSecurity(ctx, sec)
		return false, 0, &lockUntil, ErrPINLocked
	}

	_ = s.repo.UpdateAccountSecurity(ctx, sec)
	attemptsRemaining := 3 - sec.FailedAttempts
	return false, attemptsRemaining, nil, ErrInvalidPIN
}

func (s *AccountService) UpdateKYC(ctx context.Context, accNum string, req models.KYCUpdateRequest) (*models.AccountDTO, error) {
	status := req.Status
	var accountStatus string

	switch status {
	case models.KYCVerified:
		accountStatus = models.StatusActive
	case models.KYCFrozen, models.KYCRejected:
		accountStatus = models.StatusFrozen
	case models.KYCPending:
		accountStatus = models.StatusActive
	default:
		return nil, ErrInvalidKYCStatus
	}

	acc, user, err := s.repo.UpdateAccountKYC(ctx, accNum, status, accountStatus)
	if err != nil {
		if errors.Is(err, db.ErrNotFound) {
			return nil, ErrAccountNotFound
		}
		return nil, err
	}

	return models.ToAccountDTO(acc, user.FullName), nil
}

func (s *AccountService) SearchAccounts(ctx context.Context, query string) ([]models.AccountSearchResult, error) {
	return s.repo.SearchAccounts(ctx, query)
}
