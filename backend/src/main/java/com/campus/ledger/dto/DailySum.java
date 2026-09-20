package com.campus.ledger.dto;

import java.math.BigDecimal;
import java.time.LocalDate;

/** 按日期 + 收支类型汇总的查询结果 */
public class DailySum {

    private LocalDate billDate;
    private Integer type;
    private BigDecimal amount;

    public LocalDate getBillDate() {
        return billDate;
    }

    public void setBillDate(LocalDate billDate) {
        this.billDate = billDate;
    }

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
