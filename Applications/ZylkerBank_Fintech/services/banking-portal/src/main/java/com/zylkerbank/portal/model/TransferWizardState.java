package com.zylkerbank.portal.model;

import java.io.Serial;
import java.io.Serializable;
import java.math.BigDecimal;
import java.util.UUID;

/**
 * Multi-step session state holder for the P2P transfer wizard.
 * Preserves recipient selection, amount, and idempotency key across steps.
 */
public class TransferWizardState implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    private String recipientAccount;
    private String recipientName;
    private BigDecimal amount;
    private String description;
    private String idempotencyKey;

    public TransferWizardState() {
        this.idempotencyKey = UUID.randomUUID().toString();
    }

    public void generateNewIdempotencyKey() {
        this.idempotencyKey = UUID.randomUUID().toString();
    }

    public String getFormattedAmount() {
        if (amount == null) return "0.00";
        return String.format("%,.2f", amount);
    }

    public String getRecipientAccount() {
        return recipientAccount;
    }

    public void setRecipientAccount(String recipientAccount) {
        this.recipientAccount = recipientAccount;
    }

    public String getRecipientName() {
        return recipientName;
    }

    public void setRecipientName(String recipientName) {
        this.recipientName = recipientName;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public void setAmount(BigDecimal amount) {
        this.amount = amount;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    public String getIdempotencyKey() {
        return idempotencyKey;
    }

    public void setIdempotencyKey(String idempotencyKey) {
        this.idempotencyKey = idempotencyKey;
    }
}
