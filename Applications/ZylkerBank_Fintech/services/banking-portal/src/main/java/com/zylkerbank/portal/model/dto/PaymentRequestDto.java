package com.zylkerbank.portal.model.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.math.BigDecimal;

@JsonIgnoreProperties(ignoreUnknown = true)
public class PaymentRequestDto {

    @JsonProperty("request_id")
    private String requestId;

    @JsonProperty("requester_account")
    private String requesterAccount;

    @JsonProperty("requester_name")
    private String requesterName;

    @JsonProperty("payer_account")
    private String payerAccount;

    @JsonProperty("payer_name")
    private String payerName;

    @JsonProperty("amount")
    private BigDecimal amount;

    @JsonProperty("currency")
    private String currency = "USD";

    @JsonProperty("description")
    private String description;

    @JsonProperty("status")
    private String status = "REQUEST_SENT"; // REQUEST_SENT | REQUEST_SETTLED | DECLINED

    @JsonProperty("transaction_ref")
    private String transactionRef;

    @JsonProperty("created_at")
    private String createdAt;

    @JsonProperty("settled_at")
    private String settledAt;

    public String getFormattedAmount() {
        if (amount == null) return "0.00";
        return String.format("%,.2f", amount);
    }

    public boolean isPending() {
        return "REQUEST_SENT".equalsIgnoreCase(status);
    }

    public boolean isSettled() {
        return "REQUEST_SETTLED".equalsIgnoreCase(status);
    }

    public boolean isDeclined() {
        return "DECLINED".equalsIgnoreCase(status);
    }

    public String getRequestId() {
        return requestId;
    }

    public void setRequestId(String requestId) {
        this.requestId = requestId;
    }

    public String getRequesterAccount() {
        return requesterAccount;
    }

    public void setRequesterAccount(String requesterAccount) {
        this.requesterAccount = requesterAccount;
    }

    public String getRequesterName() {
        return requesterName;
    }

    public void setRequesterName(String requesterName) {
        this.requesterName = requesterName;
    }

    public String getPayerAccount() {
        return payerAccount;
    }

    public void setPayerAccount(String payerAccount) {
        this.payerAccount = payerAccount;
    }

    public String getPayerName() {
        return payerName;
    }

    public void setPayerName(String payerName) {
        this.payerName = payerName;
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

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
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

    public String getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(String createdAt) {
        this.createdAt = createdAt;
    }

    public String getSettledAt() {
        return settledAt;
    }

    public void setSettledAt(String settledAt) {
        this.settledAt = settledAt;
    }
}
