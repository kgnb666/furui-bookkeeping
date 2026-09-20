package com.campus.ledger.dto;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * 周期识别用的账单投影。
 *
 * 只需要判断周期性所需的四个字段；用投影而不是整个 Bill 实体，
 * 是为了避免把 remark、dedup_key 等与识别无关的字段也读进内存。
 */
public class RecurringBillRow {

    private String merchant;
    private String category;
    private BigDecimal amount;
    private LocalDate billDate;

    public String getMerchant() {
        return merchant;
    }

    public void setMerchant(String merchant) {
        this.merchant = merchant;
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

    public LocalDate getBillDate() {
        return billDate;
    }

    public void setBillDate(LocalDate billDate) {
        this.billDate = billDate;
    }
}
