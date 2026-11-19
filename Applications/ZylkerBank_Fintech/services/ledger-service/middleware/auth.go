package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"zylkerbank/ledger-service/config"
	"zylkerbank/ledger-service/models"
	"zylkerbank/ledger-service/security"
)

const (
	CtxKeyClaims        = "claims"
	CtxKeyUserID        = "user_id"
	CtxKeyAccountNumber = "account_number"
	CtxKeyIsInternal    = "is_internal"
	CtxKeyAuthenticated = "authenticated"
)

// AuthMiddleware extracts either Bearer JWT or X-Internal-Token
func AuthMiddleware(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		// 1. Check X-Internal-Token
		internalToken := c.GetHeader("X-Internal-Token")
		if internalToken != "" && internalToken == cfg.InternalToken {
			c.Set(CtxKeyIsInternal, true)
			c.Set(CtxKeyAuthenticated, true)
			c.Next()
			return
		}

		// 2. Check Authorization: Bearer <jwt>
		authHeader := c.GetHeader("Authorization")
		if authHeader != "" {
			parts := strings.SplitN(authHeader, " ", 2)
			if len(parts) == 2 && strings.EqualFold(parts[0], "Bearer") {
				tokenString := parts[1]
				claims, err := security.ValidateToken(cfg.JWTSecret, tokenString)
				if err == nil && claims != nil {
					c.Set(CtxKeyClaims, claims)
					c.Set(CtxKeyUserID, claims.UserID)
					c.Set(CtxKeyAccountNumber, claims.AccountNumber)
					c.Set(CtxKeyIsInternal, false)
					c.Set(CtxKeyAuthenticated, true)
					c.Next()
					return
				}
			}
		}

		// Not authenticated
		c.Set(CtxKeyAuthenticated, false)
		c.Set(CtxKeyIsInternal, false)
		c.Next()
	}
}

// RequireAuth enforces that the request has either a valid Bearer token or Internal Token
func RequireAuth() gin.HandlerFunc {
	return func(c *gin.Context) {
		authVal, exists := c.Get(CtxKeyAuthenticated)
		if !exists || !authVal.(bool) {
			c.AbortWithStatusJSON(http.StatusUnauthorized, models.ErrorResponse{
				Error:   "UNAUTHORIZED",
				Message: "Authentication required",
			})
			return
		}
		c.Next()
	}
}

// RequireInternal enforces that the request has a valid X-Internal-Token
func RequireInternal() gin.HandlerFunc {
	return func(c *gin.Context) {
		isInternal, exists := c.Get(CtxKeyIsInternal)
		if !exists || !isInternal.(bool) {
			c.AbortWithStatusJSON(http.StatusForbidden, models.ErrorResponse{
				Error:   "FORBIDDEN",
				Message: "Internal service token required",
			})
			return
		}
		c.Next()
	}
}
