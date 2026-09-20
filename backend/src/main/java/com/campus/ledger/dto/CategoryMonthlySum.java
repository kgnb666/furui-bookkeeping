package com.campus.ledger.dto;

import java.math.BigDecimal;

/**
 * 按「分类 + 月份」聚合的支出结果，用于月度上涨与频次异常的对比。
 */
public class CategoryMonthlySum {

    private String category;

    /** 格式 yyyy-MM */
    private String month;

    private BigDecimal amount;

    /** 该分类该月的支出笔数 */
    private Integer count;

    public String getCategory() {
        return category;
    }

    public void setCategory(String category) {
        this.category = category;
    }

    public String getMonth() {
        return month;
    }

    public void setMonth(String month) {
        this.month = month;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public void setAmount(BigDecimal amount) {
        this.amount = amount;
    }

    public Integer getCount() {
        return count;
    }

    public void setCount(Integer count) {
        this.count = count;
    }
}
