package com.zylkerbank.portal.model.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.util.ArrayList;
import java.util.List;

@JsonIgnoreProperties(ignoreUnknown = true)
public class RecipientSearchResultDto {

    @JsonProperty("results")
    private List<RecipientItem> results = new ArrayList<>();

    public RecipientSearchResultDto() {
    }

    public RecipientSearchResultDto(List<RecipientItem> results) {
        this.results = results;
    }

    public List<RecipientItem> getResults() {
        return results;
    }

    public void setResults(List<RecipientItem> results) {
        this.results = results;
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class RecipientItem {
        @JsonProperty("account_number")
        private String accountNumber;

        @JsonProperty("owner_name")
        private String ownerName;

        public RecipientItem() {
        }

        public RecipientItem(String accountNumber, String ownerName) {
            this.accountNumber = accountNumber;
            this.ownerName = ownerName;
        }

        public String getAccountNumber() {
            return accountNumber;
        }

        public void setAccountNumber(String accountNumber) {
            this.accountNumber = accountNumber;
        }

        public String getOwnerName() {
            return ownerName;
        }

        public void setOwnerName(String ownerName) {
            this.ownerName = ownerName;
        }
    }
}
