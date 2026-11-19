package com.zylkerbank.portal.model.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.util.ArrayList;
import java.util.List;

@JsonIgnoreProperties(ignoreUnknown = true)
public class StatementResponseDto {

    @JsonProperty("account_number")
    private String accountNumber;

    @JsonProperty("page")
    private Integer page = 1;

    @JsonProperty("page_size")
    private Integer pageSize = 20;

    @JsonProperty("total")
    private Long total = 0L;

    @JsonProperty("items")
    private List<StatementItemDto> items = new ArrayList<>();

    public int getTotalPages() {
        if (total == null || total == 0 || pageSize == null || pageSize == 0) return 1;
        return (int) Math.ceil((double) total / pageSize);
    }

    public boolean hasPrevious() {
        return page != null && page > 1;
    }

    public boolean hasNext() {
        return page != null && page < getTotalPages();
    }

    public String getAccountNumber() {
        return accountNumber;
    }

    public void setAccountNumber(String accountNumber) {
        this.accountNumber = accountNumber;
    }

    public Integer getPage() {
        return page;
    }

    public void setPage(Integer page) {
        this.page = page;
    }

    public Integer getPageSize() {
        return pageSize;
    }

    public void setPageSize(Integer pageSize) {
        this.pageSize = pageSize;
    }

    public Long getTotal() {
        return total;
    }

    public void setTotal(Long total) {
        this.total = total;
    }

    public List<StatementItemDto> getItems() {
        return items;
    }

    public void setItems(List<StatementItemDto> items) {
        this.items = items;
    }
}
