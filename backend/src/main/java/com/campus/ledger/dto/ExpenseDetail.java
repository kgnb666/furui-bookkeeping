package com.campus.ledger.dto;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * 单笔支出的轻量投影，用于计算同分类金额的中位数基线。
 *
 * 只需要定位与展示所需的四个字段，不读取 remark、dedup_key 等无关列。
 */
public class ExpenseDetail {

    private String category;
    private BigDecimal amount;
    private LocalDate billDate;
    private String merchant;

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

    public String getMerchant() {
        return merchant;
    }

    public void setMerchant(String merchant) {
        this.merchant = merchant;
    }
}
