package handlers_test

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"

	"zylkerbank/ledger-service/config"
	"zylkerbank/ledger-service/db"
	"zylkerbank/ledger-service/handlers"
	"zylkerbank/ledger-service/middleware"
	"zylkerbank/ledger-service/models"
	"zylkerbank/ledger-service/security"
	"zylkerbank/ledger-service/service"
)

// In-memory fake repository for handler integration tests
type FakeHandlerRepo struct {
	users      map[string]*models.User
	accounts   map[string]*models.Account
	securities map[string]*models.AccountSecurity
	journals   map[string]*models.JournalEntry
	postings   map[string][]models.LedgerPosting
	accSeq     int64
}

func NewFakeHandlerRepo() *FakeHandlerRepo {
	return &FakeHandlerRepo{
		users:      make(map[string]*models.User),
		accounts:   make(map[string]*models.Account),
		securities: make(map[string]*models.AccountSecurity),
		journals:   make(map[string]*models.JournalEntry),
		postings:   make(map[string][]models.LedgerPosting),
		accSeq:     2170000003,
	}
}

func (f *FakeHandlerRepo) Ping(ctx context.Context) error {
	return nil
}

func (f *FakeHandlerRepo) CreateUser(ctx context.Context, u *models.User) error {
	for _, existing := range f.users {
		if existing.Email == u.Email {
			return db.ErrDuplicateKey
		}
	}
	f.users[u.UserID] = u
	return nil
}

func (f *FakeHandlerRepo) GetUserByEmail(ctx context.Context, email string) (*models.User, error) {
	for _, u := range f.users {
		if u.Email == email {
			return u, nil
		}
	}
	return nil, db.ErrNotFound
}

func (f *FakeHandlerRepo) GetUserByID(ctx context.Context, id string) (*models.User, error) {
	if u, ok := f.users[id]; ok {
		return u, nil
	}
	return nil, db.ErrNotFound
}

func (f *FakeHandlerRepo) CreateAccount(ctx context.Context, a *models.Account) error {
	f.accounts[a.AccountID] = a
	return nil
}

func (f *FakeHandlerRepo) GetAccountByNumber(ctx context.Context, num string) (*models.Account, *models.User, error) {
	for _, a := range f.accounts {
		if a.AccountNumber == num {
			return a, f.users[a.UserID], nil
		}
	}
	return nil, nil, db.ErrNotFound
}

func (f *FakeHandlerRepo) GetAccountByID(ctx context.Context, id string) (*models.Account, *models.User, error) {
	if a, ok := f.accounts[id]; ok {
		return a, f.users[a.UserID], nil
	}
	return nil, nil, db.ErrNotFound
}

func (f *FakeHandlerRepo) GetAccountByUserID(ctx context.Context, uid string) (*models.Account, *models.User, error) {
	for _, a := range f.accounts {
		if a.UserID == uid {
			return a, f.users[a.UserID], nil
		}
	}
	return nil, nil, db.ErrNotFound
}

func (f *FakeHandlerRepo) UpdateAccountKYC(ctx context.Context, num string, kycStatus, accountStatus string) (*models.Account, *models.User, error) {
	for _, a := range f.accounts {
		if a.AccountNumber == num {
			a.KYCStatus = kycStatus
			a.AccountStatus = accountStatus
			return a, f.users[a.UserID], nil
		}
	}
	return nil, nil, db.ErrNotFound
}

func (f *FakeHandlerRepo) SearchAccounts(ctx context.Context, query string) ([]models.AccountSearchResult, error) {
	res := make([]models.AccountSearchResult, 0)
	for _, a := range f.accounts {
		if a.IsSystem == 1 {
			continue
		}
		u := f.users[a.UserID]
		res = append(res, models.AccountSearchResult{
			AccountNumber: a.AccountNumber,
			OwnerName:     u.FullName,
		})
	}
	return res, nil
}

func (f *FakeHandlerRepo) GetNextAccountNumber(ctx context.Context) (string, error) {
	f.accSeq++
	return fmt.Sprintf("%010d", f.accSeq), nil
}

func (f *FakeHandlerRepo) CreateAccountSecurity(ctx context.Context, sec *models.AccountSecurity) error {
	f.securities[sec.AccountID] = sec
	return nil
}

func (f *FakeHandlerRepo) GetAccountSecurity(ctx context.Context, id string) (*models.AccountSecurity, error) {
	if s, ok := f.securities[id]; ok {
		return s, nil
	}
	return nil, db.ErrNotFound
}

func (f *FakeHandlerRepo) UpdateAccountSecurity(ctx context.Context, sec *models.AccountSecurity) error {
	f.securities[sec.AccountID] = sec
	return nil
}

func (f *FakeHandlerRepo) GetJournalByIdempotencyKey(ctx context.Context, key string) (*models.JournalEntry, []models.LedgerPosting, error) {
	for _, j := range f.journals {
		if j.IdempotencyKey == key {
			return j, f.postings[j.JournalID], nil
		}
	}
	return nil, nil, db.ErrNotFound
}

func (f *FakeHandlerRepo) GetDailyP2PDebitTotal(ctx context.Context, id string) (float64, error) {
	return 0, nil
}

func (f *FakeHandlerRepo) ExecuteTransferTx(ctx context.Context, fromID, toID string, amount float64, j *models.JournalEntry) (*models.LedgerPosting, *models.LedgerPosting, error) {
	from := f.accounts[fromID]
	to := f.accounts[toID]
	if from.Balance < amount {
		return nil, nil, db.ErrInsufficientFunds
	}
	from.Balance -= amount
	to.Balance += amount
	f.journals[j.JournalID] = j

	debit := models.LedgerPosting{
		PostingID:      1,
		JournalID:      j.JournalID,
		AccountID:      fromID,
		EntryType:      "DEBIT",
		Amount:         amount,
		RunningBalance: from.Balance,
		CreatedAt:      time.Now(),
	}
	credit := models.LedgerPosting{
		PostingID:      2,
		JournalID:      j.JournalID,
		AccountID:      toID,
		EntryType:      "CREDIT",
		Amount:         amount,
		RunningBalance: to.Balance,
		CreatedAt:      time.Now(),
	}
	f.postings[j.JournalID] = []models.LedgerPosting{debit, credit}
	return &debit, &credit, nil
}

func (f *FakeHandlerRepo) GetStatements(ctx context.Context, num string, page, pageSize int, from, to *time.Time) ([]models.StatementItem, int, error) {
	return []models.StatementItem{
		{
			PostingID:           1,
			JournalID:           "j-1",
			TransactionRef:      "TRN-001",
			TransactionType:     "P2P_TRANSFER",
			EntryType:           "DEBIT",
			Amount:              "50.00",
			RunningBalance:      "950.00",
			Description:         "Payment",
			CounterpartyAccount: "2170000002",
			CounterpartyName:    "Bob Smith",
			CreatedAt:           time.Now().Format(time.RFC3339),
		},
	}, 1, nil
}

func setupTestRouter() (*gin.Engine, *config.Config, *FakeHandlerRepo) {
	gin.SetMode(gin.TestMode)
	repo := NewFakeHandlerRepo()
	cfg := &config.Config{
		JWTSecret:      "test-secret-12345678901234567890",
		InternalToken:  "test-internal-token",
		KYCAutoApprove: true,
		WelcomeDeposit: 1000.00,
	}

	// Seed Treasury
	tUser := &models.User{UserID: "treasury-id", Email: "treasury@test.internal", FullName: "Treasury"}
	_ = repo.CreateUser(context.Background(), tUser)
	_ = repo.CreateAccount(context.Background(), &models.Account{
		AccountID:     "treasury-acc-id",
		AccountNumber: models.SystemAccountTreasury,
		UserID:        tUser.UserID,
		Balance:       1000000.00,
		AccountStatus: models.StatusActive,
		TierLevel:     3,
		KYCStatus:     models.KYCVerified,
		IsSystem:      1,
	})

	accSvc := service.NewAccountService(repo, cfg)
	ledgerSvc := service.NewLedgerService(repo, accSvc)

	authH := handlers.NewAuthHandler(accSvc)
	accH := handlers.NewAccountsHandler(accSvc)
	ledgerH := handlers.NewLedgerHandler(ledgerSvc)
	healthH := handlers.NewHealthHandler(repo)

	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(middleware.AuthMiddleware(cfg))

	r.GET("/health", healthH.Health)

	authGroup := r.Group("/api/v1/auth")
	{
		authGroup.POST("/register", authH.Register)
		authGroup.POST("/login", authH.Login)
		authGroup.GET("/me", middleware.RequireAuth(), authH.Me)
	}

	accountsGroup := r.Group("/api/v1/accounts")
	accountsGroup.Use(middleware.RequireAuth())
	{
		accountsGroup.POST("", accH.CreateAccount)
		accountsGroup.GET("/search", accH.SearchAccounts)
		accountsGroup.GET("/:n", accH.GetAccount)
		accountsGroup.POST("/:n/verify-pin", accH.VerifyPIN)
		accountsGroup.POST("/:n/kyc", accH.UpdateKYC)
	}

	ledgerGroup := r.Group("/api/v1/ledger")
	ledgerGroup.Use(middleware.RequireAuth())
	{
		ledgerGroup.POST("/transfer", ledgerH.Transfer)
		ledgerGroup.GET("/statements/:n", ledgerH.Statements)
	}

	return r, cfg, repo
}

func TestHealthEndpoint(t *testing.T) {
	r, _, _ := setupTestRouter()
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/health", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d", w.Code)
	}
	var body map[string]interface{}
	_ = json.Unmarshal(w.Body.Bytes(), &body)
	if body["status"] != "UP" || body["service"] != "ledger-service" {
		t.Errorf("unexpected health body: %v", body)
	}
}

func TestAuthAndAccountHTTPFlow(t *testing.T) {
	r, cfg, _ := setupTestRouter()

	// 1. Register User Alice
	regPayload := `{"email":"alice@test.com","password":"Password@123","full_name":"Alice Test","pin":"1234"}`
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/v1/auth/register", bytes.NewBufferString(regPayload))
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created on register, got %d: %s", w.Code, w.Body.String())
	}
	var regResp models.RegisterResponse
	_ = json.Unmarshal(w.Body.Bytes(), &regResp)
	token := regResp.Token
	aliceAccNum := regResp.Account.AccountNumber

	// 2. GET /api/v1/auth/me with Bearer token
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("GET", "/api/v1/auth/me", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200 on /me, got %d: %s", w.Code, w.Body.String())
	}

	// 3. GET /api/v1/accounts/:n (Alice's own account)
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("GET", "/api/v1/accounts/"+aliceAccNum, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200 on get own account, got %d: %s", w.Code, w.Body.String())
	}

	// 4. GET /api/v1/accounts/:n (Other account -> 403 Forbidden)
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("GET", "/api/v1/accounts/2179999999", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	r.ServeHTTP(w, req)
	if w.Code != http.StatusForbidden {
		t.Errorf("expected 403 on get other account, got %d", w.Code)
	}

	// 5. GET /api/v1/accounts/:n with X-Internal-Token -> 200 or 404
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("GET", "/api/v1/accounts/"+aliceAccNum, nil)
	req.Header.Set("X-Internal-Token", cfg.InternalToken)
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200 with X-Internal-Token, got %d", w.Code)
	}

	// 6. Verify PIN
	pinPayload := `{"pin":"1234"}`
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("POST", "/api/v1/accounts/"+aliceAccNum+"/verify-pin", bytes.NewBufferString(pinPayload))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200 on verify-pin, got %d: %s", w.Code, w.Body.String())
	}

	// 7. Search accounts
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("GET", "/api/v1/accounts/search?q=alice", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200 on search, got %d", w.Code)
	}

	// 8. Statements
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("GET", "/api/v1/ledger/statements/"+aliceAccNum, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("expected 200 on statements, got %d", w.Code)
	}
}

func TestTransferHTTPFlow(t *testing.T) {
	r, cfg, repo := setupTestRouter()

	// Register Bob
	bobPass, _ := security.HashPassword("Password@123")
	bobPin, _ := security.HashPIN("1234")
	bUser := &models.User{UserID: "bob-uid", Email: "bob@test.com", FullName: "Bob Test", PasswordHash: bobPass}
	_ = repo.CreateUser(context.Background(), bUser)
	_ = repo.CreateAccount(context.Background(), &models.Account{
		AccountID:     "bob-acc-id",
		AccountNumber: "2170000002",
		UserID:        bUser.UserID,
		Balance:       5000.00,
		AccountStatus: models.StatusActive,
		TierLevel:     2,
		KYCStatus:     models.KYCVerified,
		IsSystem:      0,
	})
	_ = repo.CreateAccountSecurity(context.Background(), &models.AccountSecurity{
		AccountID: "bob-acc-id",
		PINHash:   bobPin,
	})

	bobToken, _ := security.GenerateToken(cfg.JWTSecret, bUser.UserID, bUser.Email, bUser.FullName, "2170000002", time.Hour)

	// Transfer $100 from Bob to Treasury
	transferPayload := `{
		"idempotency_key": "http-tx-001",
		"from_account": "2170000002",
		"to_account": "2170000000",
		"amount": "100.00",
		"description": "Donation",
		"transaction_type": "P2P_TRANSFER",
		"pin": "1234"
	}`
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("POST", "/api/v1/ledger/transfer", bytes.NewBufferString(transferPayload))
	req.Header.Set("Authorization", "Bearer "+bobToken)
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201 Created on transfer, got %d: %s", w.Code, w.Body.String())
	}

	// Idempotent replay: same request must return 200 OK + idempotent_replay: true
	w = httptest.NewRecorder()
	req, _ = http.NewRequest("POST", "/api/v1/ledger/transfer", bytes.NewBufferString(transferPayload))
	req.Header.Set("Authorization", "Bearer "+bobToken)
	req.Header.Set("Content-Type", "application/json")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 OK on replay, got %d: %s", w.Code, w.Body.String())
	}
	var replayResp models.TransferResponse
	_ = json.Unmarshal(w.Body.Bytes(), &replayResp)
	if !replayResp.IdempotentReplay {
		t.Errorf("expected idempotent_replay to be true on replay")
	}
}
