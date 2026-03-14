package handlers

import (
	"net/http"
	"strconv"

	"zylkerkart/search-service/repository"

	"github.com/gin-gonic/gin"
)

// GetSuggestions handles GET /search/suggestions?q=...&limit=8
func GetSuggestions(c *gin.Context) {
	query := c.Query("q")
	if query == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "query parameter 'q' is required"})
		return
	}

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "8"))
	if limit <= 0 || limit > 20 {
		limit = 8
	}

	suggestions, err := repository.GetSuggestions(query, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get suggestions"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"query":       query,
		"suggestions": suggestions,
	})
}

// GetTrending handles GET /search/trending?limit=10
func GetTrending(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "10"))
	if limit <= 0 || limit > 50 {
		limit = 10
	}

	trending, err := repository.GetTrending(limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get trending searches"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"trending": trending,
	})
}

// GetRecentSearches handles GET /search/recent?session_id=...&limit=5
func GetRecentSearches(c *gin.Context) {
	sessionID := c.Query("session_id")
	if sessionID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "session_id is required"})
		return
	}

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "5"))
	if limit <= 0 || limit > 20 {
		limit = 5
	}

	recent, err := repository.GetRecentSearches(sessionID, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get recent searches"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"recent": recent,
	})
}

// LogSearch handles POST /search/log
func LogSearch(c *gin.Context) {
	var req struct {
		Query        string `json:"query" binding:"required"`
		SessionID    string `json:"sessionId"`
		ResultsCount int    `json:"resultsCount"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request body"})
		return
	}

	if err := repository.LogSearch(req.Query, req.SessionID, req.ResultsCount); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to log search"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "logged"})
}
