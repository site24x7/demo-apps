package service_test

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"zylkerbank/ledger-service/config"
	"zylkerbank/ledger-service/db"
	"zylkerbank/ledger-service/models"
	"zylkerbank/ledger-service/service"
)

// FakeRepository implements db.Repository in memory for complete testability
type FakeRepository struct {
	mu            sync.Mutex
	users         map[string]*models.User
	accounts      map[string]*models.Account
	securities    map[string]*models.AccountSecurity
	journals      map[string]*models.JournalEntry
	postings      map[string][]models.LedgerPosting
	accountNumber int64
}

func NewFakeRepository() *FakeRepository {
	return &FakeRepository{
		users:         make(map[string]*models.User),
		accounts:      make(map[string]*models.Account),
		securities:    make(map[string]*models.AccountSecurity),
		journals:      make(map[string]*models.JournalEntry),
		postings:      make(map[string][]models.LedgerPosting),
		accountNumber: 2170000003,
	}
}

func (f *FakeRepository) Ping(ctx context.Context) error {
	return nil
}

func (f *FakeRepository) CreateUser(ctx context.Context, user *models.User) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, u := range f.users {
		if strings.EqualFold(u.Email, user.Email) {
			return db.ErrDuplicateKey
		}
	}
	f.users[user.UserID] = user
	return nil
}

func (f *FakeRepository) GetUserByEmail(ctx context.Context, email string) (*models.User, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, u := range f.users {
		if strings.EqualFold(u.Email, email) {
			return u, nil
		}
	}
	return nil, db.ErrNotFound
}

func (f *FakeRepository) GetUserByID(ctx context.Context, userID string) (*models.User, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	u, ok := f.users[userID]
	if !ok {
		return nil, db.ErrNotFound
	}
	return u, nil
}

func (f *FakeRepository) CreateAccount(ctx context.Context, account *models.Account) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.accounts[account.AccountID] = account
	return nil
}

func (f *FakeRepository) GetAccountByNumber(ctx context.Context, accNum string) (*models.Account, *models.User, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, a := range f.accounts {
		if a.AccountNumber == accNum {
			u := f.users[a.UserID]
			return a, u, nil
		}
	}
	return nil, nil, db.ErrNotFound
}

func (f *FakeRepository) GetAccountByID(ctx context.Context, accID string) (*models.Account, *models.User, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	a, ok := f.accounts[accID]
	if !ok {
		return nil, nil, db.ErrNotFound
	}
	u := f.users[a.UserID]
	return a, u, nil
}

func (f *FakeRepository) GetAccountByUserID(ctx context.Context, userID string) (*models.Account, *models.User, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, a := range f.accounts {
		if a.UserID == userID {
			u := f.users[a.UserID]
			return a, u, nil
		}
	}
	return nil, nil, db.ErrNotFound
}

func (f *FakeRepository) UpdateAccountKYC(ctx context.Context, accNum string, kycStatus, accountStatus string) (*models.Account, *models.User, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, a := range f.accounts {
		if a.AccountNumber == accNum {
			a.KYCStatus = kycStatus
			a.AccountStatus = accountStatus
			u := f.users[a.UserID]
			return a, u, nil
		}
	}
	return nil, nil, db.ErrNotFound
}

func (f *FakeRepository) SearchAccounts(ctx context.Context, query string) ([]models.AccountSearchResult, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	results := make([]models.AccountSearchResult, 0)
	q := strings.ToLower(query)
	for _, a := range f.accounts {
		if a.IsSystem == 1 {
			continue
		}
		u := f.users[a.UserID]
		if strings.HasPrefix(a.AccountNumber, q) || strings.Contains(strings.ToLower(u.FullName), q) || strings.Contains(strings.ToLower(u.Email), q) {
			results = append(results, models.AccountSearchResult{
				AccountNumber: a.AccountNumber,
				OwnerName:     u.FullName,
			})
		}
	}
	return results, nil
}

func (f *FakeRepository) GetNextAccountNumber(ctx context.Context) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.accountNumber++
	return fmt.Sprintf("%010d", f.accountNumber), nil
}

func (f *FakeRepository) CreateAccountSecurity(ctx context.Context, sec *models.AccountSecurity) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.securities[sec.AccountID] = sec
	return nil
}

func (f *FakeRepository) GetAccountSecurity(ctx context.Context, accID string) (*models.AccountSecurity, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	s, ok := f.securities[accID]
	if !ok {
		return nil, db.ErrNotFound
	}
	return s, nil
}

func (f *FakeRepository) UpdateAccountSecurity(ctx context.Context, sec *models.AccountSecurity) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.securities[sec.AccountID] = sec
	return nil
}

func (f *FakeRepository) GetJournalByIdempotencyKey(ctx context.Context, key string) (*models.JournalEntry, []models.LedgerPosting, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, j := range f.journals {
		if j.IdempotencyKey == key {
			return j, f.postings[j.JournalID], nil
		}
	}
	return nil, nil, db.ErrNotFound
}

func (f *FakeRepository) GetDailyP2PDebitTotal(ctx context.Context, accID string) (float64, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	var total float64
	for jID, posts := range f.postings {
		j := f.journals[jID]
		if j.TransactionType != models.TxTypeP2PTransfer {
			continue
		}
		for _, p := range posts {
			if p.AccountID == accID && p.EntryType == "DEBIT" {
				total += p.Amount
			}
		}
	}
	return total, nil
}

func (f *FakeRepository) ExecuteTransferTx(
	ctx context.Context,
	fromAccID, toAccID string,
	amount float64,
	journal *models.JournalEntry,
) (*models.LedgerPosting, *models.LedgerPosting, error) {
	f.mu.Lock()
	defer f.mu.Unlock()

	fromAcc, ok1 := f.accounts[fromAccID]
	toAcc, ok2 := f.accounts[toAccID]
	if !ok1 || !ok2 {
		return nil, nil, db.ErrNotFound
	}

	if fromAcc.AccountStatus == models.StatusFrozen || toAcc.AccountStatus == models.StatusFrozen {
		return nil, nil, db.ErrAccountFrozen
	}

	if fromAcc.Balance < amount {
		return nil, nil, db.ErrInsufficientFunds
	}

	fromAcc.Balance -= amount
	toAcc.Balance += amount

	f.journals[journal.JournalID] = journal

	debit := models.LedgerPosting{
		PostingID:      int64(len(f.postings)*2 + 1),
		JournalID:      journal.JournalID,
		AccountID:      fromAccID,
		EntryType:      "DEBIT",
		Amount:         amount,
		RunningBalance: fromAcc.Balance,
		CreatedAt:      time.Now(),
	}

	credit := models.LedgerPosting{
		PostingID:      int64(len(f.postings)*2 + 2),
		JournalID:      journal.JournalID,
		AccountID:      toAccID,
		EntryType:      "CREDIT",
		Amount:         amount,
		RunningBalance: toAcc.Balance,
		CreatedAt:      time.Now(),
	}

	f.postings[journal.JournalID] = []models.LedgerPosting{debit, credit}

	return &debit, &credit, nil
}

func (f *FakeRepository) GetStatements(
	ctx context.Context,
	accNum string,
	page, pageSize int,
	fromDate, toDate *time.Time,
) ([]models.StatementItem, int, error) {
	f.mu.Lock()
	defer f.mu.Unlock()

	var targetAcc *models.Account
	for _, a := range f.accounts {
		if a.AccountNumber == accNum {
			targetAcc = a
			break
		}
	}
	if targetAcc == nil {
		return nil, 0, db.ErrNotFound
	}

	var allItems []models.StatementItem
	for jID, posts := range f.postings {
		j := f.journals[jID]
		for _, p := range posts {
			if p.AccountID == targetAcc.AccountID {
				var cpAccNum, cpName string
				for _, other := range posts {
					if other.AccountID != targetAcc.AccountID {
						cpAcc := f.accounts[other.AccountID]
						if cpAcc != nil {
							cpAccNum = cpAcc.AccountNumber
							cpUser := f.users[cpAcc.UserID]
							if cpUser != nil {
								cpName = cpUser.FullName
							}
						}
					}
				}

				allItems = append(allItems, models.StatementItem{
					PostingID:           p.PostingID,
					JournalID:           j.JournalID,
					TransactionRef:      j.TransactionRef,
					TransactionType:     j.TransactionType,
					EntryType:           p.EntryType,
					Amount:              models.FormatMoney(p.Amount),
					RunningBalance:      models.FormatMoney(p.RunningBalance),
					Description:         j.Description,
					CounterpartyAccount: cpAccNum,
					CounterpartyName:    cpName,
					CreatedAt:           p.CreatedAt.Format(time.RFC3339),
				})
			}
		}
	}

	// Sort newest first
	sort.Slice(allItems, func(i, j int) bool {
		return allItems[i].PostingID > allItems[j].PostingID
	})

	total := len(allItems)
	start := (page - 1) * pageSize
	if start > total {
		return []models.StatementItem{}, total, nil
	}
	end := start + pageSize
	if end > total {
		end = total
	}

	return allItems[start:end], total, nil
}

// ─── UNIT TESTS ─────────────────────────────────────────────────────────────

func setupTestServices() (*service.AccountService, *service.LedgerService, *FakeRepository) {
	repo := NewFakeRepository()
	cfg := &config.Config{
		JWTSecret:      "test-secret-12345678901234567890",
		InternalToken:  "test-internal-token",
		KYCAutoApprove: true,
		WelcomeDeposit: 1000.00,
	}

	// Seed Treasury system account
	treasuryUser := &models.User{
		UserID:   "00000000-0000-0000-0000-000000000001",
		Email:    "treasury@zylkerbank.internal",
		FullName: "ZylkerBank Treasury",
	}
	_ = repo.CreateUser(context.Background(), treasuryUser)
	treasuryAcc := &models.Account{
		AccountID:     "00000000-0000-0000-0000-000000000001",
		AccountNumber: models.SystemAccountTreasury,
		UserID:        treasuryUser.UserID,
		Balance:       1000000.00,
		AccountStatus: models.StatusActive,
		TierLevel:     3,
		KYCStatus:     models.KYCVerified,
		IsSystem:      1,
	}
	_ = repo.CreateAccount(context.Background(), treasuryAcc)

	accountService := service.NewAccountService(repo, cfg)
	ledgerService := service.NewLedgerService(repo, accountService)

	return accountService, ledgerService, repo
}

func TestRegistrationAndLoginFlow(t *testing.T) {
	accountService, _, _ := setupTestServices()
	ctx := context.Background()

	// 1. Register Alice
	regReq := models.RegisterRequest{
		Email:    "alice@example.com",
		Password: "Password@123",
		FullName: "Alice Johnson",
		Phone:    "+1-555-0101",
		PIN:      "1234",
	}

	resp, err := accountService.Register(ctx, regReq)
	if err != nil {
		t.Fatalf("registration failed: %v", err)
	}

	if resp.Token == "" {
		t.Errorf("expected non-empty JWT token")
	}
	if resp.Account.Balance != "1000.00" {
		t.Errorf("expected welcome deposit balance 1000.00, got %s", resp.Account.Balance)
	}
	if resp.Account.TierLevel != 1 {
		t.Errorf("expected tier 1, got %d", resp.Account.TierLevel)
	}
	if resp.Account.KYCStatus != "VERIFIED" {
		t.Errorf("expected KYC VERIFIED, got %s", resp.Account.KYCStatus)
	}

	// 2. Duplicate registration fails with ErrEmailExists
	_, err = accountService.Register(ctx, regReq)
	if !errors.Is(err, service.ErrEmailExists) {
		t.Errorf("expected ErrEmailExists, got %v", err)
	}

	// 3. Login with valid credentials
	loginReq := models.LoginRequest{
		Email:    "alice@example.com",
		Password: "Password@123",
	}
	loginResp, err := accountService.Login(ctx, loginReq)
	if err != nil {
		t.Fatalf("login failed: %v", err)
	}
	if loginResp.User.Email != "alice@example.com" {
		t.Errorf("expected email match")
	}

	// 4. Login with invalid password
	_, err = accountService.Login(ctx, models.LoginRequest{
		Email:    "alice@example.com",
		Password: "WrongPassword",
	})
	if !errors.Is(err, service.ErrInvalidCredentials) {
		t.Errorf("expected ErrInvalidCredentials, got %v", err)
	}
}

func TestPINVerificationAndLockout(t *testing.T) {
	accountService, _, _ := setupTestServices()
	ctx := context.Background()

	regResp, err := accountService.Register(ctx, models.RegisterRequest{
		Email:    "bob@example.com",
		Password: "Password@123",
		FullName: "Bob Smith",
		PIN:      "1234",
	})
	if err != nil {
		t.Fatalf("register failed: %v", err)
	}
	accNum := regResp.Account.AccountNumber

	// 1st wrong attempt -> 2 remaining
	ok, rem, lock, err := accountService.VerifyPIN(ctx, accNum, "0000")
	if ok || rem != 2 || lock != nil || !errors.Is(err, service.ErrInvalidPIN) {
		t.Errorf("expected 2 attempts remaining, got ok=%v, rem=%d, err=%v", ok, rem, err)
	}

	// 2nd wrong attempt -> 1 remaining
	ok, rem, lock, err = accountService.VerifyPIN(ctx, accNum, "0000")
	if ok || rem != 1 || lock != nil || !errors.Is(err, service.ErrInvalidPIN) {
		t.Errorf("expected 1 attempt remaining, got ok=%v, rem=%d, err=%v", ok, rem, err)
	}

	// 3rd wrong attempt -> locked for 15 minutes
	ok, rem, lock, err = accountService.VerifyPIN(ctx, accNum, "0000")
	if ok || rem != 0 || lock == nil || !errors.Is(err, service.ErrPINLocked) {
		t.Errorf("expected PIN_LOCKED, got ok=%v, rem=%d, lock=%v, err=%v", ok, rem, lock, err)
	}

	// Subsequent attempt while locked -> returns PIN_LOCKED even with correct PIN
	ok, rem, lock, err = accountService.VerifyPIN(ctx, accNum, "1234")
	if ok || !errors.Is(err, service.ErrPINLocked) {
		t.Errorf("expected PIN_LOCKED on locked account, got err=%v", err)
	}
}

func TestTransferDoubleEntryAndLimits(t *testing.T) {
	accountService, ledgerService, _ := setupTestServices()
	ctx := context.Background()

	// Register sender (Tier 1: daily limit $1000)
	senderResp, _ := accountService.Register(ctx, models.RegisterRequest{
		Email:    "sender@example.com",
		Password: "Password@123",
		FullName: "Sender User",
		PIN:      "1234",
	})
	senderAcc := senderResp.Account.AccountNumber

	// Register receiver
	receiverResp, _ := accountService.Register(ctx, models.RegisterRequest{
		Email:    "receiver@example.com",
		Password: "Password@123",
		FullName: "Receiver User",
		PIN:      "1234",
	})
	receiverAcc := receiverResp.Account.AccountNumber

	// 1. Successful transfer ($200)
	amt200 := models.FlexibleMoney(200.00)
	txReq := models.TransferRequest{
		IdempotencyKey:  "tx-idemp-001",
		FromAccount:     senderAcc,
		ToAccount:       receiverAcc,
		Amount:          &amt200,
		Description:     "Test transfer 200",
		TransactionType: models.TxTypeP2PTransfer,
		PIN:             "1234",
	}

	txResp, err := ledgerService.Transfer(ctx, txReq)
	if err != nil {
		t.Fatalf("transfer failed: %v", err)
	}

	if txResp.FromBalanceAfter != "800.00" || txResp.ToBalanceAfter != "1200.00" {
		t.Errorf("balances incorrect after transfer: from=%s, to=%s",
			txResp.FromBalanceAfter, txResp.ToBalanceAfter)
	}
	if txResp.IdempotentReplay {
		t.Errorf("expected first transfer not to be a replay")
	}

	// 2. Idempotent replay of same key
	replayResp, err := ledgerService.Transfer(ctx, txReq)
	if err != nil {
		t.Fatalf("idempotent replay failed: %v", err)
	}
	if !replayResp.IdempotentReplay {
		t.Errorf("expected replay to have IdempotentReplay=true")
	}
	if replayResp.JournalID != txResp.JournalID {
		t.Errorf("expected same journal ID on replay")
	}

	// 3. Daily limit violation for Tier 1 (already sent $200, limit is $1000, sending $900 -> total $1100 > $1000)
	amt900 := models.FlexibleMoney(900.00)
	limitReq := models.TransferRequest{
		IdempotencyKey:  "tx-limit-002",
		FromAccount:     senderAcc,
		ToAccount:       receiverAcc,
		Amount:          &amt900,
		Description:     "Limit test",
		TransactionType: models.TxTypeP2PTransfer,
		PIN:             "1234",
	}
	_, err = ledgerService.Transfer(ctx, limitReq)
	if !errors.Is(err, service.ErrDailyLimitExceeded) {
		t.Errorf("expected ErrDailyLimitExceeded, got %v", err)
	}

	// 4. Insufficient funds
	amt5000 := models.FlexibleMoney(5000.00)
	fundsReq := models.TransferRequest{
		IdempotencyKey:  "tx-funds-003",
		FromAccount:     senderAcc,
		ToAccount:       receiverAcc,
		Amount:          &amt5000,
		Description:     "Funds test",
		TransactionType: models.TxTypeP2PTransfer,
		PIN:             "1234",
	}
	_, err = ledgerService.Transfer(ctx, fundsReq)
	if !errors.Is(err, service.ErrInsufficientFunds) && !errors.Is(err, service.ErrDailyLimitExceeded) {
		t.Errorf("expected error on insufficient funds, got %v", err)
	}

	// 5. Wrong PIN on transfer
	amt50 := models.FlexibleMoney(50.00)
	pinReq := models.TransferRequest{
		IdempotencyKey:  "tx-pin-004",
		FromAccount:     senderAcc,
		ToAccount:       receiverAcc,
		Amount:          &amt50,
		Description:     "PIN test",
		TransactionType: models.TxTypeP2PTransfer,
		PIN:             "9999",
	}
	_, err = ledgerService.Transfer(ctx, pinReq)
	var customErr *service.CustomError
	if !errors.As(err, &customErr) || customErr.Code != "INVALID_PIN" {
		t.Errorf("expected INVALID_PIN custom error, got %v", err)
	}

	// 6. Same account transfer rejected
	sameReq := models.TransferRequest{
		IdempotencyKey:  "tx-same-005",
		FromAccount:     senderAcc,
		ToAccount:       senderAcc,
		Amount:          &amt50,
		TransactionType: models.TxTypeP2PTransfer,
		PIN:             "1234",
	}
	_, err = ledgerService.Transfer(ctx, sameReq)
	if !errors.Is(err, service.ErrSameAccount) {
		t.Errorf("expected ErrSameAccount, got %v", err)
	}

	// 7. Verify Statements with counterparty and running balance
	stmtResp, err := ledgerService.GetStatements(ctx, senderAcc, 1, 20, nil, nil)
	if err != nil {
		t.Fatalf("get statements failed: %v", err)
	}
	if stmtResp.Total < 2 {
		t.Errorf("expected at least 2 statement items (welcome + transfer), got %d", stmtResp.Total)
	}
	// Check newest item (the $200 transfer)
	latest := stmtResp.Items[0]
	if latest.EntryType != "DEBIT" || latest.Amount != "200.00" || latest.RunningBalance != "800.00" {
		t.Errorf("statement item unexpected: %+v", latest)
	}
	if latest.CounterpartyAccount != receiverAcc {
		t.Errorf("expected counterparty account %s, got %s", receiverAcc, latest.CounterpartyAccount)
	}
}

func TestKYCFreezeAndUnverified(t *testing.T) {
	accountService, ledgerService, _ := setupTestServices()
	ctx := context.Background()

	regResp, _ := accountService.Register(ctx, models.RegisterRequest{
		Email:    "frozen@example.com",
		Password: "Password@123",
		FullName: "Frozen User",
		PIN:      "1234",
	})
	accNum := regResp.Account.AccountNumber

	// Freeze account via KYC endpoint
	updatedAcc, err := accountService.UpdateKYC(ctx, accNum, models.KYCUpdateRequest{
		Status: "FROZEN",
	})
	if err != nil {
		t.Fatalf("freeze KYC failed: %v", err)
	}
	if updatedAcc.AccountStatus != "FROZEN" {
		t.Errorf("expected account status FROZEN, got %s", updatedAcc.AccountStatus)
	}

	// Attempt transfer from frozen account
	amt := models.FlexibleMoney(10.00)
	_, err = ledgerService.Transfer(ctx, models.TransferRequest{
		IdempotencyKey:  "tx-frozen-001",
		FromAccount:     accNum,
		ToAccount:       models.SystemAccountTreasury,
		Amount:          &amt,
		TransactionType: models.TxTypeP2PTransfer,
		PIN:             "1234",
	})
	if !errors.Is(err, service.ErrAccountFrozen) {
		t.Errorf("expected ErrAccountFrozen, got %v", err)
	}
}
