package com.zylkerbank.portal.model.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.io.Serial;
import java.io.Serializable;
import java.math.BigDecimal;
import java.util.Map;

@JsonIgnoreProperties(ignoreUnknown = true)
public class TransferResultDto implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    @JsonProperty("status")
    private String status;

    @JsonProperty("transaction_ref")
    private String transactionRef;

    @JsonProperty("journal_id")
    private String journalId;

    @JsonProperty("amount")
    private BigDecimal amount;

    @JsonProperty("currency")
    private String currency = "USD";

    @JsonProperty("from_account")
    private String fromAccount;

    @JsonProperty("to_account")
    private String toAccount;

    @JsonProperty("recipient_name")
    private String recipientName;

    @JsonProperty("description")
    private String description;

    @JsonProperty("risk")
    private Map<String, Object> risk;

    @JsonProperty("new_balance")
    private BigDecimal newBalance;

    @JsonProperty("created_at")
    private String createdAt;

    @JsonProperty("idempotent_replay")
    private Boolean idempotentReplay = false;

    public String getFormattedAmount() {
        if (amount == null) return "0.00";
        return String.format("%,.2f", amount);
    }

    public String getFormattedNewBalance() {
        if (newBalance == null) return "0.00";
        return String.format("%,.2f", newBalance);
    }

    public String getCounterpartyAccount() {
        return toAccount;
    }

    public String getTimestamp() {
        return createdAt;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public String getTransactionRef() {
        return transactionRef;
    }

    public void setTransactionRef(String transactionRef) {
        this.transactionRef = transactionRef;
    }

    public String getJournalId() {
        return journalId;
    }

    public void setJournalId(String journalId) {
        this.journalId = journalId;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public void setAmount(BigDecimal amount) {
        this.amount = amount;
    }

    public String getCurrency() {
        return currency;
    }

    public void setCurrency(String currency) {
        this.currency = currency;
    }

    public String getFromAccount() {
        return fromAccount;
    }

    public void setFromAccount(String fromAccount) {
        this.fromAccount = fromAccount;
    }

    public String getToAccount() {
        return toAccount;
    }

    public void setToAccount(String toAccount) {
        this.toAccount = toAccount;
    }

    public String getRecipientName() {
        return recipientName;
    }

    public void setRecipientName(String recipientName) {
        this.recipientName = recipientName;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    public Map<String, Object> getRisk() {
        return risk;
    }

    public void setRisk(Map<String, Object> risk) {
        this.risk = risk;
    }

    public BigDecimal getNewBalance() {
        return newBalance;
    }

    public void setNewBalance(BigDecimal newBalance) {
        this.newBalance = newBalance;
    }

    public String getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(String createdAt) {
        this.createdAt = createdAt;
    }

    public Boolean getIdempotentReplay() {
        return idempotentReplay;
    }

    public void setIdempotentReplay(Boolean idempotentReplay) {
        this.idempotentReplay = idempotentReplay;
    }
}
