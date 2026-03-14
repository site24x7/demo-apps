package models

import "time"

// SearchLog represents a logged search query
type SearchLog struct {
	ID           int64     `json:"id"`
	Query        string    `json:"query"`
	SessionID    string    `json:"session_id"`
	ResultsCount int       `json:"results_count"`
	CreatedAt    time.Time `json:"created_at"`
}

// SearchLogRequest is the request body for logging a search
type SearchLogRequest struct {
	Query        string `json:"query" binding:"required"`
	SessionID    string `json:"sessionId"`
	ResultsCount int    `json:"resultsCount"`
}

// Suggestion represents an autocomplete suggestion
type Suggestion struct {
	Text     string `json:"text"`
	Category string `json:"category,omitempty"`
}

// TrendingSearch represents a trending search term
type TrendingSearch struct {
	Query string `json:"query"`
	Count int    `json:"count"`
}
