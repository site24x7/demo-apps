package handlers

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"zylkerbank/ledger-service/middleware"
	"zylkerbank/ledger-service/models"
	"zylkerbank/ledger-service/service"
)

type AuthHandler struct {
	accountService *service.AccountService
}

func NewAuthHandler(accountService *service.AccountService) *AuthHandler {
	return &AuthHandler{accountService: accountService}
}

func (h *AuthHandler) Register(c *gin.Context) {
	var req models.RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.ErrorResponse{
			Error:   "INVALID_REQUEST",
			Message: err.Error(),
		})
		return
	}

	resp, err := h.accountService.Register(c.Request.Context(), req)
	if err != nil {
		if errors.Is(err, service.ErrEmailExists) {
			c.JSON(http.StatusConflict, models.ErrorResponse{
				Error:   "EMAIL_EXISTS",
				Message: "Email is already registered",
			})
			return
		}
		if errors.Is(err, service.ErrInvalidPINFormat) {
			c.JSON(http.StatusBadRequest, models.ErrorResponse{
				Error:   "INVALID_PIN_FORMAT",
				Message: "PIN must be between 4 and 6 digits",
			})
			return
		}
		c.JSON(http.StatusInternalServerError, models.ErrorResponse{
			Error:   "INTERNAL_SERVER_ERROR",
			Message: err.Error(),
		})
		return
	}

	c.JSON(http.StatusCreated, resp)
}

func (h *AuthHandler) Login(c *gin.Context) {
	var req models.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, models.ErrorResponse{
			Error:   "INVALID_REQUEST",
			Message: err.Error(),
		})
		return
	}

	resp, err := h.accountService.Login(c.Request.Context(), req)
	if err != nil {
		if errors.Is(err, service.ErrInvalidCredentials) {
			c.JSON(http.StatusUnauthorized, models.ErrorResponse{
				Error:   "INVALID_CREDENTIALS",
				Message: "Invalid email or password",
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

func (h *AuthHandler) Me(c *gin.Context) {
	userIDVal, exists := c.Get(middleware.CtxKeyUserID)
	if !exists {
		c.JSON(http.StatusUnauthorized, models.ErrorResponse{
			Error:   "UNAUTHORIZED",
			Message: "Authentication required",
		})
		return
	}
	userID := userIDVal.(string)

	accDTO, userDTO, err := h.accountService.GetAccountByUserID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusNotFound, models.ErrorResponse{
			Error:   "ACCOUNT_NOT_FOUND",
			Message: "Account not found for authenticated user",
		})
		return
	}

	c.JSON(http.StatusOK, models.MeResponse{
		User:    *userDTO,
		Account: accDTO,
	})
}
