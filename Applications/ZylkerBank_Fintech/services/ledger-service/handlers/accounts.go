package handlers

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"zylkerbank/ledger-service/middleware"
	"zylkerbank/ledger-service/models"
	"zylkerbank/ledger-service/service"
)

type AccountsHandler struct {
	accountService *service.AccountService
}

func NewAccountsHandler(accountService *service.AccountService) *AccountsHandler {
	return &AccountsHandler{accountService: accountService}
}

func (h *AccountsHandler) CreateAccount(c *gin.Context) {
	var req models.CreateAccountRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.ErrorResponse{
			Error:   "INVALID_REQUEST",
			Message: err.Error(),
		})
		return
	}

	acc, err := h.accountService.CreateAccount(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.ErrorResponse{
			Error:   "INTERNAL_SERVER_ERROR",
			Message: err.Error(),
		})
		return
	}

	c.JSON(http.StatusCreated, acc)
}

func (h *AccountsHandler) GetAccount(c *gin.Context) {
	accNum := c.Param("n")

	// Authorization check: either internal call or own account
	isInternal, _ := c.Get(middleware.CtxKeyIsInternal)
	callerAcc, _ := c.Get(middleware.CtxKeyAccountNumber)

	if (isInternal == nil || !isInternal.(bool)) && callerAcc != accNum {
		c.JSON(http.StatusForbidden, models.ErrorResponse{
			Error:   "FORBIDDEN",
			Message: "Access denied to this account",
		})
		return
	}

	acc, err := h.accountService.GetAccountByNumber(c.Request.Context(), accNum)
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

	c.JSON(http.StatusOK, acc)
}

func (h *AccountsHandler) SearchAccounts(c *gin.Context) {
	query := c.Query("q")
	results, err := h.accountService.SearchAccounts(c.Request.Context(), query)
	if err != nil {
		c.JSON(http.StatusInternalServerError, models.ErrorResponse{
			Error:   "INTERNAL_SERVER_ERROR",
			Message: err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, models.SearchResponse{
		Results: results,
	})
}

func (h *AccountsHandler) VerifyPIN(c *gin.Context) {
	accNum := c.Param("n")

	// Authorization check: internal or own account
	isInternal, _ := c.Get(middleware.CtxKeyIsInternal)
	callerAcc, _ := c.Get(middleware.CtxKeyAccountNumber)

	if (isInternal == nil || !isInternal.(bool)) && callerAcc != accNum {
		c.JSON(http.StatusForbidden, models.ErrorResponse{
			Error:   "FORBIDDEN",
			Message: "Access denied to verify PIN for this account",
		})
		return
	}

	var req models.VerifyPINRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.ErrorResponse{
			Error:   "INVALID_REQUEST",
			Message: err.Error(),
		})
		return
	}

	verified, attemptsRemaining, lockedUntil, err := h.accountService.VerifyPIN(c.Request.Context(), accNum, req.PIN)
	if err != nil {
		if errors.Is(err, service.ErrPINLocked) {
			lockedStr := ""
			if lockedUntil != nil {
				lockedStr = lockedUntil.Format("2006-01-02T15:04:05Z07:00")
			}
			c.JSON(http.StatusLocked, models.ErrorResponse{
				Error:             "PIN_LOCKED",
				Message:           "PIN is locked due to too many failed attempts",
				AttemptsRemaining: &attemptsRemaining,
				LockedUntil:       lockedStr,
			})
			return
		}
		if errors.Is(err, service.ErrInvalidPIN) {
			c.JSON(http.StatusUnauthorized, models.ErrorResponse{
				Error:             "INVALID_PIN",
				Message:           "Invalid security PIN",
				AttemptsRemaining: &attemptsRemaining,
			})
			return
		}
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

	c.JSON(http.StatusOK, models.VerifyPINResponse{
		Verified: verified,
	})
}

func (h *AccountsHandler) UpdateKYC(c *gin.Context) {
	accNum := c.Param("n")

	var req models.KYCUpdateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.ErrorResponse{
			Error:   "INVALID_REQUEST",
			Message: err.Error(),
		})
		return
	}

	acc, err := h.accountService.UpdateKYC(c.Request.Context(), accNum, req)
	if err != nil {
		if errors.Is(err, service.ErrInvalidKYCStatus) {
			c.JSON(http.StatusBadRequest, models.ErrorResponse{
				Error:   "INVALID_KYC_STATUS",
				Message: "Invalid KYC status specified",
			})
			return
		}
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

	c.JSON(http.StatusOK, acc)
}
