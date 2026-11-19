package com.zylkerbank.portal.model;

import java.io.Serial;
import java.io.Serializable;
import java.math.BigDecimal;

/**
 * Multi-step session state holder for the Payment Request wizard.
 */
public class ReceiveWizardState implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    private String payerAccount;
    private String payerName;
    private BigDecimal amount;
    private String description;

    public ReceiveWizardState() {
    }

    public String getFormattedAmount() {
        if (amount == null) return "0.00";
        return String.format("%,.2f", amount);
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

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }
}
