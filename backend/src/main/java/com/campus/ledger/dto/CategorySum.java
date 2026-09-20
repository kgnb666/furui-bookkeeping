package com.campus.ledger.dto;

import java.math.BigDecimal;

/** 按分类汇总的查询结果 */
public class CategorySum {

    private String category;
    private BigDecimal amount;

    public String getCategory() {
        return category;
    }

    public void setCategory(String category) {
        this.category = category;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public void setAmount(BigDecimal amount) {
        this.amount = amount;
    }
}
