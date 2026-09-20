package com.campus.ledger.dto;

import java.math.BigDecimal;
import java.time.LocalDate;

/** 按「日期 + 分类」聚合的支出结果，预算预测用来判断某分类本月有几天在消费 */
public class CategoryDailySum {

    private LocalDate billDate;
    private String category;
    private BigDecimal amount;

    public LocalDate getBillDate() {
        return billDate;
    }

    public void setBillDate(LocalDate billDate) {
        this.billDate = billDate;
    }

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
