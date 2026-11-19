package models_test

import (
	"encoding/json"
	"testing"
	"time"

	"zylkerbank/ledger-service/models"
)

func TestFlexibleMoney(t *testing.T) {
	// Test JSON number
	jsonNum := []byte(`{"amount": 123.45}`)
	var reqNum struct {
		Amount models.FlexibleMoney `json:"amount"`
	}
	if err := json.Unmarshal(jsonNum, &reqNum); err != nil {
		t.Fatalf("failed to unmarshal JSON number: %v", err)
	}
	if reqNum.Amount.Float64() != 123.45 {
		t.Errorf("expected 123.45, got %f", reqNum.Amount.Float64())
	}

	// Test JSON string
	jsonStr := []byte(`{"amount": "678.90"}`)
	var reqStr struct {
		Amount models.FlexibleMoney `json:"amount"`
	}
	if err := json.Unmarshal(jsonStr, &reqStr); err != nil {
		t.Fatalf("failed to unmarshal JSON string: %v", err)
	}
	if reqStr.Amount.Float64() != 678.90 {
		t.Errorf("expected 678.90, got %f", reqStr.Amount.Float64())
	}

	// Test invalid money
	jsonInvalid := []byte(`{"amount": "not-a-number"}`)
	var reqInvalid struct {
		Amount models.FlexibleMoney `json:"amount"`
	}
	if err := json.Unmarshal(jsonInvalid, &reqInvalid); err == nil {
		t.Errorf("expected error unmarshaling invalid money")
	}
}

func TestFormatMoney(t *testing.T) {
	tests := []struct {
		input    float64
		expected string
	}{
		{0.0, "0.00"},
		{100.5, "100.50"},
		{8500.0, "8500.00"},
		{123.456, "123.46"},
	}

	for _, tt := range tests {
		got := models.FormatMoney(tt.input)
		if got != tt.expected {
			t.Errorf("FormatMoney(%f) = %s, expected %s", tt.input, got, tt.expected)
		}
	}
}

func TestTierDailyLimit(t *testing.T) {
	if models.TierDailyLimit(1) != "1000.00" {
		t.Errorf("expected Tier 1 limit 1000.00, got %s", models.TierDailyLimit(1))
	}
	if models.TierDailyLimit(2) != "10000.00" {
		t.Errorf("expected Tier 2 limit 10000.00, got %s", models.TierDailyLimit(2))
	}
	if models.TierDailyLimit(3) != "UNLIMITED" {
		t.Errorf("expected Tier 3 limit UNLIMITED, got %s", models.TierDailyLimit(3))
	}
}

func TestToAccountDTO(t *testing.T) {
	now := time.Now()
	acc := &models.Account{
		AccountID:     "acc-123",
		AccountNumber: "2170000001",
		UserID:        "user-123",
		Currency:      "USD",
		Balance:       8500.00,
		AccountStatus: models.StatusActive,
		TierLevel:     2,
		KYCStatus:     models.KYCVerified,
		IsSystem:      0,
		CreatedAt:     now,
	}

	dto := models.ToAccountDTO(acc, "Alice Johnson")
	if dto.AccountID != "acc-123" || dto.OwnerName != "Alice Johnson" || dto.Balance != "8500.00" || dto.DailyLimit != "10000.00" {
		t.Errorf("unexpected DTO: %+v", dto)
	}
}
