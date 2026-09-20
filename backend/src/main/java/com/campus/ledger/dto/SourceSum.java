package com.campus.ledger.dto;

import java.math.BigDecimal;

/** 按支付来源汇总的查询结果 */
public class SourceSum {

    private String source;
    private BigDecimal amount;

    public String getSource() {
        return source;
    }

    public void setSource(String source) {
        this.source = source;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public void setAmount(BigDecimal amount) {
        this.amount = amount;
    }
}
