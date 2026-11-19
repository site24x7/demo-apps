package com.zylkerbank.portal.model.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.math.BigDecimal;

@JsonIgnoreProperties(ignoreUnknown = true)
public class CardDto {

    @JsonProperty("card_id")
    private String cardId;

    @JsonProperty("user_id")
    private String userId;

    @JsonProperty("account_number")
    private String accountNumber;

    @JsonProperty("card_number_masked")
    private String cardNumberMasked;

    @JsonProperty("card_number")
    private String cardNumber; // only returned upon creation

    @JsonProperty("cvv")
    private String cvv; // only returned upon creation

    @JsonProperty("card_holder_name")
    private String cardHolderName;

    @JsonProperty("card_type")
    private String cardType = "VISA";

    @JsonProperty("expiry_month")
    private Integer expiryMonth;

    @JsonProperty("expiry_year")
    private Integer expiryYear;

    @JsonProperty("spending_limit")
    private BigDecimal spendingLimit;

    @JsonProperty("balance")
    private BigDecimal balance;

    @JsonProperty("is_frozen")
    private Boolean isFrozen = false;

    @JsonProperty("created_at")
    private String createdAt;

    public String getFormattedBalance() {
        if (balance == null) return "0.00";
        return String.format("%,.2f", balance);
    }

    public String getFormattedSpendingLimit() {
        if (spendingLimit == null) return "0.00";
        return String.format("%,.2f", spendingLimit);
    }

    public String getFormattedExpiry() {
        if (expiryMonth == null || expiryYear == null) return "12/28";
        return String.format("%02d/%02d", expiryMonth, expiryYear % 100);
    }

    public String getCardId() {
        return cardId;
    }

    public void setCardId(String cardId) {
        this.cardId = cardId;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getAccountNumber() {
        return accountNumber;
    }

    public void setAccountNumber(String accountNumber) {
        this.accountNumber = accountNumber;
    }

    public String getCardNumberMasked() {
        return cardNumberMasked;
    }

    public void setCardNumberMasked(String cardNumberMasked) {
        this.cardNumberMasked = cardNumberMasked;
    }

    public String getCardNumber() {
        return cardNumber;
    }

    public void setCardNumber(String cardNumber) {
        this.cardNumber = cardNumber;
    }

    public String getCvv() {
        return cvv;
    }

    public void setCvv(String cvv) {
        this.cvv = cvv;
    }

    public String getCardHolderName() {
        return cardHolderName;
    }

    public void setCardHolderName(String cardHolderName) {
        this.cardHolderName = cardHolderName;
    }

    public String getCardType() {
        return cardType;
    }

    public void setCardType(String cardType) {
        this.cardType = cardType;
    }

    public Integer getExpiryMonth() {
        return expiryMonth;
    }

    public void setExpiryMonth(Integer expiryMonth) {
        this.expiryMonth = expiryMonth;
    }

    public Integer getExpiryYear() {
        return expiryYear;
    }

    public void setExpiryYear(Integer expiryYear) {
        this.expiryYear = expiryYear;
    }

    public BigDecimal getSpendingLimit() {
        return spendingLimit;
    }

    public void setSpendingLimit(BigDecimal spendingLimit) {
        this.spendingLimit = spendingLimit;
    }

    public BigDecimal getBalance() {
        return balance;
    }

    public void setBalance(BigDecimal balance) {
        this.balance = balance;
    }

    public Boolean getIsFrozen() {
        return isFrozen != null && isFrozen;
    }

    public void setIsFrozen(Boolean isFrozen) {
        this.isFrozen = isFrozen;
    }

    public String getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(String createdAt) {
        this.createdAt = createdAt;
    }
}
