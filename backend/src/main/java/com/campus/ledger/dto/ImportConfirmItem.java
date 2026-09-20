package com.campus.ledger.dto;

import com.fasterxml.jackson.annotation.JsonFormat;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * 用户确认导入的一条记录（分类、类型等可能已经在预览页被修改过）。
 */
public class ImportConfirmItem {

    @JsonFormat(pattern = "yyyy-MM-dd")
    private LocalDate billDate;

    /** 原始交易时间，仅在缺少交易号时用于计算去重指纹 */
    private String sourceTradeTime;

    private String merchant;
    private String remark;
    private BigDecimal amount;
    private String type;
    private String category;
    private String sourceTradeId;

    public LocalDate getBillDate() {
        return billDate;
    }

    public void setBillDate(LocalDate billDate) {
        this.billDate = billDate;
    }

    public String getSourceTradeTime() {
        return sourceTradeTime;
    }

    public void setSourceTradeTime(String sourceTradeTime) {
        this.sourceTradeTime = sourceTradeTime;
    }

    public String getMerchant() {
        return merchant;
    }

    public void setMerchant(String merchant) {
        this.merchant = merchant;
    }

    public String getRemark() {
        return remark;
    }

    public void setRemark(String remark) {
        this.remark = remark;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public void setAmount(BigDecimal amount) {
        this.amount = amount;
    }

    public String getType() {
        return type;
    }

    public void setType(String type) {
        this.type = type;
    }

    public String getCategory() {
        return category;
    }

    public void setCategory(String category) {
        this.category = category;
    }

    public String getSourceTradeId() {
        return sourceTradeId;
    }

    public void setSourceTradeId(String sourceTradeId) {
        this.sourceTradeId = sourceTradeId;
    }
}
