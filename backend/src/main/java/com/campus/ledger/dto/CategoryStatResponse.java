package com.campus.ledger.dto;

import java.math.BigDecimal;

/** 分类支出统计，percentage 由后端算好后返回 */
public class CategoryStatResponse {

    private final String category;
    private final String amount;
    private final BigDecimal percentage;

    public CategoryStatResponse(String category, String amount, BigDecimal percentage) {
        this.category = category;
        this.amount = amount;
        this.percentage = percentage;
    }

    public String getCategory() {
        return category;
    }

    public String getAmount() {
        return amount;
    }

    public BigDecimal getPercentage() {
        return percentage;
    }
}
