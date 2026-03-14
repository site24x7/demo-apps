package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"zylkerkart/search-service/config"
	"zylkerkart/search-service/models"
)

// GetSuggestions returns autocomplete suggestions from the product catalog
func GetSuggestions(query string, limit int) ([]models.Suggestion, error) {
	ctx := context.Background()
	cacheKey := fmt.Sprintf("search:suggestions:%s:%d", strings.ToLower(query), limit)

	// Try Redis cache first
	if config.RDB != nil {
		cached, err := config.RDB.Get(ctx, cacheKey).Result()
		if err == nil {
			var suggestions []models.Suggestion
			if json.Unmarshal([]byte(cached), &suggestions) == nil {
				return suggestions, nil
			}
		}
	}

	// Query product catalog (cross-database read from db_product)
	sqlQuery := `
		SELECT p.title, COALESCE(s.name, '') AS category FROM db_product.products p
		LEFT JOIN db_product.subcategories s ON p.subcategory_id = s.id
		WHERE p.title LIKE ? OR p.product_description LIKE ?
		ORDER BY
			CASE WHEN p.title LIKE ? THEN 0 ELSE 1 END,
			p.ratings_count DESC
		LIMIT ?
	`
	searchTerm := "%" + query + "%"
	prefixTerm := query + "%"

	rows, err := config.DB.Query(sqlQuery, searchTerm, searchTerm, prefixTerm, limit)
	if err != nil {
		return nil, fmt.Errorf("query failed: %w", err)
	}
	defer rows.Close()

	var suggestions []models.Suggestion
	for rows.Next() {
		var s models.Suggestion
		if err := rows.Scan(&s.Text, &s.Category); err != nil {
			continue
		}
		suggestions = append(suggestions, s)
	}

	// Cache for 10 minutes
	if config.RDB != nil && len(suggestions) > 0 {
		data, _ := json.Marshal(suggestions)
		config.RDB.Set(ctx, cacheKey, data, 10*time.Minute)
	}

	return suggestions, nil
}

// LogSearch records a search query
func LogSearch(query, sessionID string, resultsCount int) error {
	_, err := config.DB.Exec(
		"INSERT INTO search_logs (query, session_id, results_count) VALUES (?, ?, ?)",
		query, sessionID, resultsCount,
	)
	if err != nil {
		return fmt.Errorf("failed to log search: %w", err)
	}

	// Invalidate trending cache
	if config.RDB != nil {
		ctx := context.Background()
		config.RDB.Del(ctx, "search:trending")

		// Add to recent searches for this session
		if sessionID != "" {
			recentKey := fmt.Sprintf("search:recent:%s", sessionID)
			config.RDB.LPush(ctx, recentKey, query)
			config.RDB.LTrim(ctx, recentKey, 0, 9) // Keep last 10
			config.RDB.Expire(ctx, recentKey, 2*time.Hour)
		}
	}

	return nil
}

// GetTrending returns the most popular searches in the last 24 hours
func GetTrending(limit int) ([]models.TrendingSearch, error) {
	ctx := context.Background()
	cacheKey := "search:trending"

	// Try Redis cache first
	if config.RDB != nil {
		cached, err := config.RDB.Get(ctx, cacheKey).Result()
		if err == nil {
			var trending []models.TrendingSearch
			if json.Unmarshal([]byte(cached), &trending) == nil {
				return trending, nil
			}
		}
	}

	rows, err := config.DB.Query(
		`SELECT query, COUNT(*) as cnt FROM search_logs
		 WHERE created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)
		 GROUP BY query ORDER BY cnt DESC LIMIT ?`,
		limit,
	)
	if err != nil {
		return nil, fmt.Errorf("query failed: %w", err)
	}
	defer rows.Close()

	var trending []models.TrendingSearch
	for rows.Next() {
		var t models.TrendingSearch
		if err := rows.Scan(&t.Query, &t.Count); err != nil {
			continue
		}
		trending = append(trending, t)
	}

	// Cache for 5 minutes
	if config.RDB != nil && len(trending) > 0 {
		data, _ := json.Marshal(trending)
		config.RDB.Set(ctx, cacheKey, data, 5*time.Minute)
	}

	return trending, nil
}

// GetRecentSearches returns recent searches for a session
func GetRecentSearches(sessionID string, limit int) ([]string, error) {
	if config.RDB == nil || sessionID == "" {
		return []string{}, nil
	}

	ctx := context.Background()
	recentKey := fmt.Sprintf("search:recent:%s", sessionID)

	results, err := config.RDB.LRange(ctx, recentKey, 0, int64(limit-1)).Result()
	if err != nil {
		return []string{}, nil
	}

	// Deduplicate
	seen := make(map[string]bool)
	var unique []string
	for _, q := range results {
		if !seen[q] {
			seen[q] = true
			unique = append(unique, q)
		}
	}

	return unique, nil
}
