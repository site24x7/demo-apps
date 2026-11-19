package handlers

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"zylkerbank/ledger-service/db"
)

type HealthHandler struct {
	repo db.Repository
}

func NewHealthHandler(repo db.Repository) *HealthHandler {
	return &HealthHandler{repo: repo}
}

func (h *HealthHandler) Health(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()

	oracleStatus := "UP"
	if err := h.repo.Ping(ctx); err != nil {
		oracleStatus = "DOWN"
	}

	overallStatus := "UP"
	statusCode := http.StatusOK
	if oracleStatus != "UP" {
		overallStatus = "DEGRADED"
		// 503 if primary database is down
		statusCode = http.StatusServiceUnavailable
	}

	c.JSON(statusCode, gin.H{
		"service": "ledger-service",
		"status":  overallStatus,
		"checks": gin.H{
			"oracle": gin.H{
				"status": oracleStatus,
			},
		},
	})
}
