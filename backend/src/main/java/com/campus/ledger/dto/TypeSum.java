package com.campus.ledger.dto;

import java.math.BigDecimal;

/** 按收支类型汇总的查询结果 */
public class TypeSum {

    private Integer type;
    private BigDecimal amount;

    public Integer getType() {
        return type;
    }

    public void setType(Integer type) {
        this.type = type;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public void setAmount(BigDecimal amount) {
        this.amount = amount;
    }
}
