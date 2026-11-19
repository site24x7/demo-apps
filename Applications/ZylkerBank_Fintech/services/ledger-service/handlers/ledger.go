package handlers

import (
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"

	"zylkerbank/ledger-service/middleware"
	"zylkerbank/ledger-service/models"
	"zylkerbank/ledger-service/service"
)

type LedgerHandler struct {
	ledgerService *service.LedgerService
}

func NewLedgerHandler(ledgerService *service.LedgerService) *LedgerHandler {
	return &LedgerHandler{ledgerService: ledgerService}
}

func (h *LedgerHandler) Transfer(c *gin.Context) {
	var req models.TransferRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.ErrorResponse{
			Error:   "INVALID_REQUEST",
			Message: err.Error(),
		})
		return
	}

	// Authorization check: either internal call or caller owns the from_account
	isInternal, _ := c.Get(middleware.CtxKeyIsInternal)
	callerAcc, _ := c.Get(middleware.CtxKeyAccountNumber)

	if (isInternal == nil || !isInternal.(bool)) && callerAcc != req.FromAccount {
		c.JSON(http.StatusForbidden, models.ErrorResponse{
			Error:   "FORBIDDEN",
			Message: "Access denied to debit from this account",
		})
		return
	}

	resp, err := h.ledgerService.Transfer(c.Request.Context(), req)
	if err != nil {
		var customErr *service.CustomError
		if errors.As(err, &customErr) {
			lockedStr := ""
			if customErr.LockedUntil != nil {
				lockedStr = customErr.LockedUntil.Format(time.RFC3339)
			}
			c.JSON(customErr.Status, models.ErrorResponse{
				Error:             customErr.Code,
				Message:           customErr.Message,
				AttemptsRemaining: customErr.AttemptsRemaining,
				LockedUntil:       lockedStr,
			})
			return
		}

		if errors.Is(err, service.ErrInvalidAmount) {
			c.JSON(http.StatusBadRequest, models.ErrorResponse{
				Error:   "INVALID_AMOUNT",
				Message: "Transfer amount must be greater than zero",
			})
			return
		}
		if errors.Is(err, service.ErrSameAccount) {
			c.JSON(http.StatusBadRequest, models.ErrorResponse{
				Error:   "SAME_ACCOUNT",
				Message: "Cannot transfer to the same account",
			})
			return
		}
		if errors.Is(err, service.ErrInvalidTxType) {
			c.JSON(http.StatusBadRequest, models.ErrorResponse{
				Error:   "INVALID_TRANSACTION_TYPE",
				Message: "Invalid transaction type",
			})
			return
		}
		if errors.Is(err, service.ErrAccountNotFound) {
			c.JSON(http.StatusNotFound, models.ErrorResponse{
				Error:   "ACCOUNT_NOT_FOUND",
				Message: "Source or destination account not found",
			})
			return
		}
		if errors.Is(err, service.ErrAccountFrozen) {
			c.JSON(http.StatusForbidden, models.ErrorResponse{
				Error:   "ACCOUNT_FROZEN",
				Message: "Account is frozen",
			})
			return
		}
		if errors.Is(err, service.ErrKYCNotVerified) {
			c.JSON(http.StatusForbidden, models.ErrorResponse{
				Error:   "KYC_NOT_VERIFIED",
				Message: "Account KYC is not verified",
			})
			return
		}
		if errors.Is(err, service.ErrDailyLimitExceeded) {
			c.JSON(http.StatusForbidden, models.ErrorResponse{
				Error:   "DAILY_LIMIT_EXCEEDED",
				Message: "Transfer exceeds daily limit for account tier",
			})
			return
		}
		if errors.Is(err, service.ErrInsufficientFunds) {
			c.JSON(http.StatusUnprocessableEntity, models.ErrorResponse{
				Error:   "INSUFFICIENT_FUNDS",
				Message: "Insufficient funds for transfer",
			})
			return
		}
		if errors.Is(err, service.ErrInvalidPIN) {
			c.JSON(http.StatusUnauthorized, models.ErrorResponse{
				Error:   "INVALID_PIN",
				Message: "PIN is required",
			})
			return
		}

		c.JSON(http.StatusInternalServerError, models.ErrorResponse{
			Error:   "INTERNAL_SERVER_ERROR",
			Message: err.Error(),
		})
		return
	}

	if resp.IdempotentReplay {
		c.JSON(http.StatusOK, resp)
		return
	}

	c.JSON(http.StatusCreated, resp)
}

func (h *LedgerHandler) Statements(c *gin.Context) {
	accNum := c.Param("n")

	// Authorization check: internal or own account
	isInternal, _ := c.Get(middleware.CtxKeyIsInternal)
	callerAcc, _ := c.Get(middleware.CtxKeyAccountNumber)

	if (isInternal == nil || !isInternal.(bool)) && callerAcc != accNum {
		c.JSON(http.StatusForbidden, models.ErrorResponse{
			Error:   "FORBIDDEN",
			Message: "Access denied to statements for this account",
		})
		return
	}

	page := 1
	if pStr := c.Query("page"); pStr != "" {
		if p, err := strconv.Atoi(pStr); err == nil && p > 0 {
			page = p
		}
	}

	pageSize := 20
	if psStr := c.Query("page_size"); psStr != "" {
		if ps, err := strconv.Atoi(psStr); err == nil && ps > 0 && ps <= 100 {
			pageSize = ps
		}
	}

	var fromDate, toDate *time.Time
	if fromStr := c.Query("from"); fromStr != "" {
		if t, err := time.Parse(time.RFC3339, fromStr); err == nil {
			fromDate = &t
		} else if t, err := time.Parse("2006-01-02", fromStr); err == nil {
			fromDate = &t
		}
	}
	if toStr := c.Query("to"); toStr != "" {
		if t, err := time.Parse(time.RFC3339, toStr); err == nil {
			toDate = &t
		} else if t, err := time.Parse("2006-01-02", toStr); err == nil {
			toDate = &t
		}
	}

	resp, err := h.ledgerService.GetStatements(c.Request.Context(), accNum, page, pageSize, fromDate, toDate)
	if err != nil {
		if errors.Is(err, service.ErrAccountNotFound) {
			c.JSON(http.StatusNotFound, models.ErrorResponse{
				Error:   "ACCOUNT_NOT_FOUND",
				Message: "Account not found",
			})
			return
		}
		c.JSON(http.StatusInternalServerError, models.ErrorResponse{
			Error:   "INTERNAL_SERVER_ERROR",
			Message: err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, resp)
}
