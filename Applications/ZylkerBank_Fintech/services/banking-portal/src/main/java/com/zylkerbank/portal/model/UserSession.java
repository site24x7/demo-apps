package com.zylkerbank.portal.model;

import java.io.Serial;
import java.io.Serializable;
import java.math.BigDecimal;
import java.util.Objects;

/**
 * Session-backed representation of the authenticated customer.
 * Implements Serializable for Spring Session JDBC persistence in PostgreSQL.
 */
public class UserSession implements Serializable {

    @Serial
    private static final long serialVersionUID = 1L;

    private String userId;
    private String email;
    private String fullName;
    private String phone;
    private String accountNumber;
    private String token;
    private BigDecimal balance;
    private Integer tierLevel;
    private String kycStatus;

    public UserSession() {
    }

    public UserSession(String userId, String email, String fullName, String phone, String accountNumber, String token) {
        this.userId = userId;
        this.email = email;
        this.fullName = fullName;
        this.phone = phone;
        this.accountNumber = accountNumber;
        this.token = token;
        this.balance = BigDecimal.ZERO;
        this.tierLevel = 1;
        this.kycStatus = "VERIFIED";
    }

    public String getFirstName() {
        if (fullName == null || fullName.trim().isEmpty()) {
            return "Customer";
        }
        return fullName.trim().split("\\s+")[0];
    }

    public String getFormattedBalance() {
        if (balance == null) {
            return "0.00";
        }
        return String.format("%,.2f", balance);
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }

    public String getFullName() {
        return fullName;
    }

    public void setFullName(String fullName) {
        this.fullName = fullName;
    }

    public String getPhone() {
        return phone;
    }

    public void setPhone(String phone) {
        this.phone = phone;
    }

    public String getAccountNumber() {
        return accountNumber;
    }

    public void setAccountNumber(String accountNumber) {
        this.accountNumber = accountNumber;
    }

    public String getToken() {
        return token;
    }

    public void setToken(String token) {
        this.token = token;
    }

    public BigDecimal getBalance() {
        return balance;
    }

    public void setBalance(BigDecimal balance) {
        this.balance = balance;
    }

    public Integer getTierLevel() {
        return tierLevel;
    }

    public void setTierLevel(Integer tierLevel) {
        this.tierLevel = tierLevel;
    }

    public String getKycStatus() {
        return kycStatus;
    }

    public void setKycStatus(String kycStatus) {
        this.kycStatus = kycStatus;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        UserSession that = (UserSession) o;
        return Objects.equals(userId, that.userId) && Objects.equals(accountNumber, that.accountNumber);
    }

    @Override
    public int hashCode() {
        return Objects.hash(userId, accountNumber);
    }
}
