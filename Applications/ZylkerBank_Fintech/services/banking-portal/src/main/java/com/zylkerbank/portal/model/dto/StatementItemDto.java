package com.zylkerbank.portal.model.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.math.BigDecimal;

@JsonIgnoreProperties(ignoreUnknown = true)
public class StatementItemDto {

    @JsonProperty("posting_id")
    private Long postingId;

    @JsonProperty("journal_id")
    private String journalId;

    @JsonProperty("transaction_ref")
    private String transactionRef;

    @JsonProperty("transaction_type")
    private String transactionType;

    @JsonProperty("entry_type")
    private String entryType; // DEBIT or CREDIT

    @JsonProperty("amount")
    private BigDecimal amount;

    @JsonProperty("running_balance")
    private BigDecimal runningBalance;

    @JsonProperty("description")
    private String description;

    @JsonProperty("counterparty_account")
    private String counterpartyAccount;

    @JsonProperty("counterparty_name")
    private String counterpartyName;

    @JsonProperty("created_at")
    private String createdAt;

    public boolean isCredit() {
        return "CREDIT".equalsIgnoreCase(entryType);
    }

    public String getFormattedAmount() {
        if (amount == null) return "0.00";
        return (isCredit() ? "+" : "-") + "$" + String.format("%,.2f", amount);
    }

    public String getFormattedRunningBalance() {
        if (runningBalance == null) return "0.00";
        return "$" + String.format("%,.2f", runningBalance);
    }

    public Long getPostingId() {
        return postingId;
    }

    public void setPostingId(Long postingId) {
        this.postingId = postingId;
    }

    public String getJournalId() {
        return journalId;
    }

    public void setJournalId(String journalId) {
        this.journalId = journalId;
    }

    public String getTransactionRef() {
        return transactionRef;
    }

    public void setTransactionRef(String transactionRef) {
        this.transactionRef = transactionRef;
    }

    public String getTransactionType() {
        return transactionType;
    }

    public void setTransactionType(String transactionType) {
        this.transactionType = transactionType;
    }

    public String getEntryType() {
        return entryType;
    }

    public void setEntryType(String entryType) {
        this.entryType = entryType;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public void setAmount(BigDecimal amount) {
        this.amount = amount;
    }

    public BigDecimal getRunningBalance() {
        return runningBalance;
    }

    public void setRunningBalance(BigDecimal runningBalance) {
        this.runningBalance = runningBalance;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    public String getCounterpartyAccount() {
        return counterpartyAccount;
    }

    public void setCounterpartyAccount(String counterpartyAccount) {
        this.counterpartyAccount = counterpartyAccount;
    }

    public String getCounterpartyName() {
        return counterpartyName;
    }

    public void setCounterpartyName(String counterpartyName) {
        this.counterpartyName = counterpartyName;
    }

    public String getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(String createdAt) {
        this.createdAt = createdAt;
    }
}
