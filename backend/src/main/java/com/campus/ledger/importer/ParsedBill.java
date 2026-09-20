package com.campus.ledger.importer;

import com.campus.ledger.common.BillType;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * 账单文件中的一行，解析后统一成这个样子再交给导入服务。
 */
public class ParsedBill {

    private int rowIndex;
    private LocalDate billDate;
    /** 原始交易时间文本，参与去重指纹计算 */
    private String sourceTradeTime;
    private BillType type;
    private BigDecimal amount;
    private String merchant = "";
    private String remark = "";
    private String sourceTradeId;
    /** 支付宝自带的交易分类，作为推荐分类的提示 */
    private String categoryHint;
    private boolean parseFailed;
    private String failReason;

    public void fail(String reason) {
        this.parseFailed = true;
        this.failReason = reason;
    }

    public int getRowIndex() {
        return rowIndex;
    }

    public void setRowIndex(int rowIndex) {
        this.rowIndex = rowIndex;
    }

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

    public BillType getType() {
        return type;
    }

    public void setType(BillType type) {
        this.type = type;
    }

    public BigDecimal getAmount() {
        return amount;
    }

    public void setAmount(BigDecimal amount) {
        this.amount = amount;
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

    public String getSourceTradeId() {
        return sourceTradeId;
    }

    public void setSourceTradeId(String sourceTradeId) {
        this.sourceTradeId = sourceTradeId;
    }

    public String getCategoryHint() {
        return categoryHint;
    }

    public void setCategoryHint(String categoryHint) {
        this.categoryHint = categoryHint;
    }

    public boolean isParseFailed() {
        return parseFailed;
    }

    public String getFailReason() {
        return failReason;
    }
}
