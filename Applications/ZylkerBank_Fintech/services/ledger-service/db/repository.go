package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"zylkerbank/ledger-service/models"
)

var (
	ErrNotFound          = errors.New("record not found")
	ErrInsufficientFunds = errors.New("insufficient funds")
	ErrAccountFrozen     = errors.New("account is frozen")
	ErrDuplicateKey      = errors.New("duplicate key")
)

type Repository interface {
	// User
	CreateUser(ctx context.Context, user *models.User) error
	GetUserByEmail(ctx context.Context, email string) (*models.User, error)
	GetUserByID(ctx context.Context, userID string) (*models.User, error)

	// Account
	CreateAccount(ctx context.Context, account *models.Account) error
	GetAccountByNumber(ctx context.Context, accNum string) (*models.Account, *models.User, error)
	GetAccountByID(ctx context.Context, accID string) (*models.Account, *models.User, error)
	GetAccountByUserID(ctx context.Context, userID string) (*models.Account, *models.User, error)
	UpdateAccountKYC(ctx context.Context, accNum string, kycStatus, accountStatus string) (*models.Account, *models.User, error)
	SearchAccounts(ctx context.Context, query string) ([]models.AccountSearchResult, error)
	GetNextAccountNumber(ctx context.Context) (string, error)

	// Security
	CreateAccountSecurity(ctx context.Context, sec *models.AccountSecurity) error
	GetAccountSecurity(ctx context.Context, accID string) (*models.AccountSecurity, error)
	UpdateAccountSecurity(ctx context.Context, sec *models.AccountSecurity) error

	// Journal & Ledger
	GetJournalByIdempotencyKey(ctx context.Context, key string) (*models.JournalEntry, []models.LedgerPosting, error)
	GetDailyP2PDebitTotal(ctx context.Context, accID string) (float64, error)
	ExecuteTransferTx(ctx context.Context, fromAccID, toAccID string, amount float64, journal *models.JournalEntry) (*models.LedgerPosting, *models.LedgerPosting, error)

	// Statements
	GetStatements(ctx context.Context, accNum string, page, pageSize int, fromDate, toDate *time.Time) ([]models.StatementItem, int, error)

	// Raw DB ping for health
	Ping(ctx context.Context) error
}

type OracleRepository struct {
	db *sql.DB
}

func NewOracleRepository(db *sql.DB) *OracleRepository {
	return &OracleRepository{db: db}
}

func (r *OracleRepository) Ping(ctx context.Context) error {
	return r.db.PingContext(ctx)
}

// User methods

func (r *OracleRepository) CreateUser(ctx context.Context, user *models.User) error {
	query := `INSERT INTO users (user_id, email, password_hash, full_name, phone, created_at)
              VALUES (:1, :2, :3, :4, :5, CURRENT_TIMESTAMP)`
	_, err := r.db.ExecContext(ctx, query, user.UserID, user.Email, user.PasswordHash, user.FullName, user.Phone)
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "unique") || strings.Contains(err.Error(), "ORA-00001") {
			return ErrDuplicateKey
		}
		return err
	}
	return nil
}

func (r *OracleRepository) GetUserByEmail(ctx context.Context, email string) (*models.User, error) {
	query := `SELECT user_id, email, password_hash, full_name, NVL(phone, ''), created_at
              FROM users WHERE LOWER(email) = LOWER(:1)`
	row := r.db.QueryRowContext(ctx, query, email)

	var u models.User
	var phone sql.NullString
	err := row.Scan(&u.UserID, &u.Email, &u.PasswordHash, &u.FullName, &phone, &u.CreatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	if phone.Valid {
		u.Phone = phone.String
	}
	return &u, nil
}

func (r *OracleRepository) GetUserByID(ctx context.Context, userID string) (*models.User, error) {
	query := `SELECT user_id, email, password_hash, full_name, NVL(phone, ''), created_at
              FROM users WHERE user_id = :1`
	row := r.db.QueryRowContext(ctx, query, userID)

	var u models.User
	var phone sql.NullString
	err := row.Scan(&u.UserID, &u.Email, &u.PasswordHash, &u.FullName, &phone, &u.CreatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	if phone.Valid {
		u.Phone = phone.String
	}
	return &u, nil
}

// Account methods

func (r *OracleRepository) CreateAccount(ctx context.Context, account *models.Account) error {
	query := `INSERT INTO accounts (account_id, account_number, user_id, currency, balance, account_status, tier_level, kyc_status, is_system, created_at)
              VALUES (:1, :2, :3, :4, :5, :6, :7, :8, :9, CURRENT_TIMESTAMP)`
	_, err := r.db.ExecContext(ctx, query,
		account.AccountID,
		account.AccountNumber,
		account.UserID,
		account.Currency,
		account.Balance,
		account.AccountStatus,
		account.TierLevel,
		account.KYCStatus,
		account.IsSystem,
	)
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "unique") || strings.Contains(err.Error(), "ORA-00001") {
			return ErrDuplicateKey
		}
		return err
	}
	return nil
}

func (r *OracleRepository) GetAccountByNumber(ctx context.Context, accNum string) (*models.Account, *models.User, error) {
	query := `SELECT a.account_id, a.account_number, a.user_id, a.currency, a.balance,
                     a.account_status, a.tier_level, a.kyc_status, a.is_system, a.created_at,
                     u.email, u.full_name, NVL(u.phone, ''), u.created_at
              FROM accounts a
              JOIN users u ON a.user_id = u.user_id
              WHERE a.account_number = :1`
	row := r.db.QueryRowContext(ctx, query, accNum)

	var a models.Account
	var u models.User
	var phone sql.NullString
	err := row.Scan(
		&a.AccountID, &a.AccountNumber, &a.UserID, &a.Currency, &a.Balance,
		&a.AccountStatus, &a.TierLevel, &a.KYCStatus, &a.IsSystem, &a.CreatedAt,
		&u.Email, &u.FullName, &phone, &u.CreatedAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil, ErrNotFound
		}
		return nil, nil, err
	}
	u.UserID = a.UserID
	if phone.Valid {
		u.Phone = phone.String
	}
	return &a, &u, nil
}

func (r *OracleRepository) GetAccountByID(ctx context.Context, accID string) (*models.Account, *models.User, error) {
	query := `SELECT a.account_id, a.account_number, a.user_id, a.currency, a.balance,
                     a.account_status, a.tier_level, a.kyc_status, a.is_system, a.created_at,
                     u.email, u.full_name, NVL(u.phone, ''), u.created_at
              FROM accounts a
              JOIN users u ON a.user_id = u.user_id
              WHERE a.account_id = :1`
	row := r.db.QueryRowContext(ctx, query, accID)

	var a models.Account
	var u models.User
	var phone sql.NullString
	err := row.Scan(
		&a.AccountID, &a.AccountNumber, &a.UserID, &a.Currency, &a.Balance,
		&a.AccountStatus, &a.TierLevel, &a.KYCStatus, &a.IsSystem, &a.CreatedAt,
		&u.Email, &u.FullName, &phone, &u.CreatedAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil, ErrNotFound
		}
		return nil, nil, err
	}
	u.UserID = a.UserID
	if phone.Valid {
		u.Phone = phone.String
	}
	return &a, &u, nil
}

func (r *OracleRepository) GetAccountByUserID(ctx context.Context, userID string) (*models.Account, *models.User, error) {
	query := `SELECT a.account_id, a.account_number, a.user_id, a.currency, a.balance,
                     a.account_status, a.tier_level, a.kyc_status, a.is_system, a.created_at,
                     u.email, u.full_name, NVL(u.phone, ''), u.created_at
              FROM accounts a
              JOIN users u ON a.user_id = u.user_id
              WHERE a.user_id = :1`
	row := r.db.QueryRowContext(ctx, query, userID)

	var a models.Account
	var u models.User
	var phone sql.NullString
	err := row.Scan(
		&a.AccountID, &a.AccountNumber, &a.UserID, &a.Currency, &a.Balance,
		&a.AccountStatus, &a.TierLevel, &a.KYCStatus, &a.IsSystem, &a.CreatedAt,
		&u.Email, &u.FullName, &phone, &u.CreatedAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil, ErrNotFound
		}
		return nil, nil, err
	}
	u.UserID = a.UserID
	if phone.Valid {
		u.Phone = phone.String
	}
	return &a, &u, nil
}

func (r *OracleRepository) UpdateAccountKYC(ctx context.Context, accNum string, kycStatus, accountStatus string) (*models.Account, *models.User, error) {
	query := `UPDATE accounts SET kyc_status = :1, account_status = :2 WHERE account_number = :3`
	res, err := r.db.ExecContext(ctx, query, kycStatus, accountStatus, accNum)
	if err != nil {
		return nil, nil, err
	}
	rowsAffected, _ := res.RowsAffected()
	if rowsAffected == 0 {
		return nil, nil, ErrNotFound
	}
	return r.GetAccountByNumber(ctx, accNum)
}

func (r *OracleRepository) SearchAccounts(ctx context.Context, query string) ([]models.AccountSearchResult, error) {
	trimmed := strings.TrimSpace(query)
	if trimmed == "" {
		return []models.AccountSearchResult{}, nil
	}

	isAllDigits := true
	for _, c := range trimmed {
		if c < '0' || c > '9' {
			isAllDigits = false
			break
		}
	}

	var rows *sql.Rows
	var err error

	if isAllDigits {
		sqlStr := `SELECT a.account_number, u.full_name
                   FROM accounts a
                   JOIN users u ON a.user_id = u.user_id
                   WHERE a.is_system = 0 AND a.account_number LIKE :1 || '%'
                   ORDER BY a.account_number
                   OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY`
		rows, err = r.db.QueryContext(ctx, sqlStr, trimmed)
	} else {
		sqlStr := `SELECT a.account_number, u.full_name
                   FROM accounts a
                   JOIN users u ON a.user_id = u.user_id
                   WHERE a.is_system = 0 AND (LOWER(u.full_name) LIKE '%' || LOWER(:1) || '%' OR LOWER(u.email) LIKE '%' || LOWER(:2) || '%')
                   ORDER BY u.full_name
                   OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY`
		rows, err = r.db.QueryContext(ctx, sqlStr, trimmed, trimmed)
	}

	if err != nil {
		return nil, err
	}
	defer rows.Close()

	results := make([]models.AccountSearchResult, 0)
	for rows.Next() {
		var item models.AccountSearchResult
		if err := rows.Scan(&item.AccountNumber, &item.OwnerName); err != nil {
			return nil, err
		}
		results = append(results, item)
	}
	return results, nil
}

func (r *OracleRepository) GetNextAccountNumber(ctx context.Context) (string, error) {
	query := `SELECT COALESCE(MAX(TO_NUMBER(account_number)), 2170000003) + 1
              FROM accounts
              WHERE account_number LIKE '217%' AND is_system = 0`
	var nextNum int64
	err := r.db.QueryRowContext(ctx, query).Scan(&nextNum)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%010d", nextNum), nil
}

// Security methods

func (r *OracleRepository) CreateAccountSecurity(ctx context.Context, sec *models.AccountSecurity) error {
	query := `INSERT INTO account_security (account_id, pin_hash, failed_attempts, locked_until)
              VALUES (:1, :2, :3, :4)`
	_, err := r.db.ExecContext(ctx, query, sec.AccountID, sec.PINHash, sec.FailedAttempts, sec.LockedUntil)
	return err
}

func (r *OracleRepository) GetAccountSecurity(ctx context.Context, accID string) (*models.AccountSecurity, error) {
	query := `SELECT account_id, pin_hash, failed_attempts, locked_until
              FROM account_security WHERE account_id = :1`
	row := r.db.QueryRowContext(ctx, query, accID)

	var sec models.AccountSecurity
	var locked sql.NullTime
	err := row.Scan(&sec.AccountID, &sec.PINHash, &sec.FailedAttempts, &locked)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	if locked.Valid {
		sec.LockedUntil = &locked.Time
	}
	return &sec, nil
}

func (r *OracleRepository) UpdateAccountSecurity(ctx context.Context, sec *models.AccountSecurity) error {
	query := `UPDATE account_security
              SET pin_hash = :1, failed_attempts = :2, locked_until = :3
              WHERE account_id = :4`
	_, err := r.db.ExecContext(ctx, query, sec.PINHash, sec.FailedAttempts, sec.LockedUntil, sec.AccountID)
	return err
}

// Journal & Ledger methods

func (r *OracleRepository) GetJournalByIdempotencyKey(ctx context.Context, key string) (*models.JournalEntry, []models.LedgerPosting, error) {
	jQuery := `SELECT journal_id, transaction_ref, idempotency_key, transaction_type, NVL(description, ''), created_at
               FROM journal_entries WHERE idempotency_key = :1`
	row := r.db.QueryRowContext(ctx, jQuery, key)

	var j models.JournalEntry
	err := row.Scan(&j.JournalID, &j.TransactionRef, &j.IdempotencyKey, &j.TransactionType, &j.Description, &j.CreatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil, ErrNotFound
		}
		return nil, nil, err
	}

	pQuery := `SELECT posting_id, journal_id, account_id, entry_type, amount, running_balance, created_at
               FROM ledger_postings WHERE journal_id = :1 ORDER BY posting_id ASC`
	rows, err := r.db.QueryContext(ctx, pQuery, j.JournalID)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()

	postings := make([]models.LedgerPosting, 0)
	for rows.Next() {
		var p models.LedgerPosting
		if err := rows.Scan(&p.PostingID, &p.JournalID, &p.AccountID, &p.EntryType, &p.Amount, &p.RunningBalance, &p.CreatedAt); err != nil {
			return nil, nil, err
		}
		postings = append(postings, p)
	}

	return &j, postings, nil
}

func (r *OracleRepository) GetDailyP2PDebitTotal(ctx context.Context, accID string) (float64, error) {
	query := `SELECT COALESCE(SUM(lp.amount), 0)
              FROM ledger_postings lp
              JOIN journal_entries j ON lp.journal_id = j.journal_id
              WHERE lp.account_id = :1
                AND lp.entry_type = 'DEBIT'
                AND j.transaction_type = 'P2P_TRANSFER'
                AND lp.created_at >= TRUNC(CURRENT_TIMESTAMP)`
	var total float64
	err := r.db.QueryRowContext(ctx, query, accID).Scan(&total)
	if err != nil {
		return 0, err
	}
	return total, nil
}

func (r *OracleRepository) ExecuteTransferTx(
	ctx context.Context,
	fromAccID, toAccID string,
	amount float64,
	journal *models.JournalEntry,
) (*models.LedgerPosting, *models.LedgerPosting, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, nil, err
	}
	defer tx.Rollback()

	// Deadlock-free row locking: order accounts alphabetically/lexicographically by account_id
	firstID, secondID := fromAccID, toAccID
	if firstID > secondID {
		firstID, secondID = toAccID, fromAccID
	}

	lockQuery := `SELECT account_id, balance, account_status FROM accounts WHERE account_id = :1 FOR UPDATE`

	var id1, id2 string
	var bal1, bal2 float64
	var status1, status2 string

	if err := tx.QueryRowContext(ctx, lockQuery, firstID).Scan(&id1, &bal1, &status1); err != nil {
		return nil, nil, fmt.Errorf("failed to lock account %s: %w", firstID, err)
	}
	if err := tx.QueryRowContext(ctx, lockQuery, secondID).Scan(&id2, &bal2, &status2); err != nil {
		return nil, nil, fmt.Errorf("failed to lock account %s: %w", secondID, err)
	}

	var fromBal, toBal float64
	var fromStatus, toStatus string
	if firstID == fromAccID {
		fromBal, fromStatus = bal1, status1
		toBal, toStatus = bal2, status2
	} else {
		fromBal, fromStatus = bal2, status2
		toBal, toStatus = bal1, status1
	}

	if fromStatus == models.StatusFrozen || toStatus == models.StatusFrozen {
		return nil, nil, ErrAccountFrozen
	}

	if fromBal < amount {
		return nil, nil, ErrInsufficientFunds
	}

	newFromBal := fromBal - amount
	newToBal := toBal + amount

	// Update balances
	updQuery := `UPDATE accounts SET balance = :1 WHERE account_id = :2`
	if _, err := tx.ExecContext(ctx, updQuery, newFromBal, fromAccID); err != nil {
		return nil, nil, fmt.Errorf("failed to update source balance: %w", err)
	}
	if _, err := tx.ExecContext(ctx, updQuery, newToBal, toAccID); err != nil {
		return nil, nil, fmt.Errorf("failed to update destination balance: %w", err)
	}

	// Insert journal entry
	insJournal := `INSERT INTO journal_entries (journal_id, transaction_ref, idempotency_key, transaction_type, description, created_at)
                   VALUES (:1, :2, :3, :4, :5, CURRENT_TIMESTAMP)`
	if _, err := tx.ExecContext(ctx, insJournal, journal.JournalID, journal.TransactionRef, journal.IdempotencyKey, journal.TransactionType, journal.Description); err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "unique") || strings.Contains(err.Error(), "ORA-00001") {
			return nil, nil, ErrDuplicateKey
		}
		return nil, nil, fmt.Errorf("failed to insert journal entry: %w", err)
	}

	now := time.Now()
	// Insert DEBIT posting
	insPosting := `INSERT INTO ledger_postings (journal_id, account_id, entry_type, amount, running_balance, created_at)
                   VALUES (:1, :2, :3, :4, :5, CURRENT_TIMESTAMP)`
	if _, err := tx.ExecContext(ctx, insPosting, journal.JournalID, fromAccID, "DEBIT", amount, newFromBal); err != nil {
		return nil, nil, fmt.Errorf("failed to insert debit posting: %w", err)
	}

	// Insert CREDIT posting
	if _, err := tx.ExecContext(ctx, insPosting, journal.JournalID, toAccID, "CREDIT", amount, newToBal); err != nil {
		return nil, nil, fmt.Errorf("failed to insert credit posting: %w", err)
	}

	if err := tx.Commit(); err != nil {
		return nil, nil, fmt.Errorf("failed to commit transfer transaction: %w", err)
	}

	debitPosting := &models.LedgerPosting{
		JournalID:      journal.JournalID,
		AccountID:      fromAccID,
		EntryType:      "DEBIT",
		Amount:         amount,
		RunningBalance: newFromBal,
		CreatedAt:      now,
	}

	creditPosting := &models.LedgerPosting{
		JournalID:      journal.JournalID,
		AccountID:      toAccID,
		EntryType:      "CREDIT",
		Amount:         amount,
		RunningBalance: newToBal,
		CreatedAt:      now,
	}

	return debitPosting, creditPosting, nil
}

// Statements methods

func (r *OracleRepository) GetStatements(
	ctx context.Context,
	accNum string,
	page, pageSize int,
	fromDate, toDate *time.Time,
) ([]models.StatementItem, int, error) {
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}
	offset := (page - 1) * pageSize

	baseConditions := `WHERE a.account_number = :1`
	args := []interface{}{accNum}
	argIdx := 2

	if fromDate != nil {
		baseConditions += fmt.Sprintf(" AND lp.created_at >= :%d", argIdx)
		args = append(args, *fromDate)
		argIdx++
	}
	if toDate != nil {
		baseConditions += fmt.Sprintf(" AND lp.created_at <= :%d", argIdx)
		args = append(args, *toDate)
		argIdx++
	}

	countQuery := fmt.Sprintf(`SELECT COUNT(*)
                               FROM ledger_postings lp
                               JOIN accounts a ON lp.account_id = a.account_id
                               %s`, baseConditions)

	var total int
	err := r.db.QueryRowContext(ctx, countQuery, args...).Scan(&total)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to count statements: %w", err)
	}

	dataQuery := fmt.Sprintf(`SELECT 
                                  lp.posting_id,
                                  j.journal_id,
                                  j.transaction_ref,
                                  j.transaction_type,
                                  lp.entry_type,
                                  lp.amount,
                                  lp.running_balance,
                                  NVL(j.description, ''),
                                  NVL(cp_acc.account_number, ''),
                                  NVL(cp_user.full_name, ''),
                                  lp.created_at
                              FROM ledger_postings lp
                              JOIN journal_entries j ON lp.journal_id = j.journal_id
                              JOIN accounts a ON lp.account_id = a.account_id
                              LEFT JOIN ledger_postings cp_lp ON cp_lp.journal_id = j.journal_id AND cp_lp.account_id != lp.account_id
                              LEFT JOIN accounts cp_acc ON cp_acc.account_id = cp_lp.account_id
                              LEFT JOIN users cp_user ON cp_user.user_id = cp_acc.user_id
                              %s
                              ORDER BY lp.created_at DESC, lp.posting_id DESC
                              OFFSET :%d ROWS FETCH NEXT :%d ROWS ONLY`,
		baseConditions, argIdx, argIdx+1)

	queryArgs := append(args, offset, pageSize)
	rows, err := r.db.QueryContext(ctx, dataQuery, queryArgs...)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to query statements: %w", err)
	}
	defer rows.Close()

	items := make([]models.StatementItem, 0)
	for rows.Next() {
		var item models.StatementItem
		var amt, runBal float64
		var createdAt time.Time
		err := rows.Scan(
			&item.PostingID,
			&item.JournalID,
			&item.TransactionRef,
			&item.TransactionType,
			&item.EntryType,
			&amt,
			&runBal,
			&item.Description,
			&item.CounterpartyAccount,
			&item.CounterpartyName,
			&createdAt,
		)
		if err != nil {
			return nil, 0, fmt.Errorf("failed to scan statement row: %w", err)
		}
		item.Amount = models.FormatMoney(amt)
		item.RunningBalance = models.FormatMoney(runBal)
		item.CreatedAt = createdAt.Format(time.RFC3339)
		items = append(items, item)
	}

	return items, total, nil
}
